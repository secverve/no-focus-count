import {
  app,
  BrowserWindow,
  dialog,
  globalShortcut,
  ipcMain,
  Notification,
  powerMonitor,
  safeStorage,
  screen,
  shell
} from 'electron';
import { activeWindow, openWindows } from 'get-windows';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  displayForBounds,
  evaluateFocus,
  mergeSettings,
  nextBreakSeconds,
  todayFocusSeconds
} from './core.mjs';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const isWayland = process.platform === 'linux' && process.env.XDG_SESSION_TYPE === 'wayland';
const isDevelopment = !app.isPackaged;

let dashboardWindow;
let overlayWindow;
let dataFile;
let state;
let tickBusy = false;
let saveTimer;
let overlayInteractiveTimer;
let systemPowerInactive = false;

function freshRuntime(settings) {
  return {
    phase: 'idle',
    mode: 'focus',
    suggestedMode: 'focus',
    remainingSeconds: settings.focusMinutes * 60,
    completedCycles: 0,
    currentSession: null,
    currentEventIndex: null,
    lastContext: null
  };
}

async function loadState() {
  dataFile = path.join(app.getPath('userData'), 'state.json');
  try {
    const stored = JSON.parse(await fs.readFile(dataFile, 'utf8'));
    const settings = mergeSettings(stored.settings);
    return {
      version: 3,
      updatedAt: stored.updatedAt ?? new Date().toISOString(),
      settings,
      history: Array.isArray(stored.history) ? stored.history : [],
      runtime: freshRuntime(settings)
    };
  } catch {
    const settings = mergeSettings();
    return {
      version: 3,
      updatedAt: new Date().toISOString(),
      settings,
      history: [],
      runtime: freshRuntime(settings)
    };
  }
}

function publicState() {
  const safeSettings = structuredClone(state.settings);
  safeSettings.sync.tokenEncrypted = undefined;
  safeSettings.sync.hasToken = Boolean(state.settings.sync.tokenEncrypted);
  return {
    ...structuredClone(state),
    settings: safeSettings,
    analytics: {
      todayFocusSeconds: todayFocusSeconds(state.history),
      dailyGoalSeconds: state.settings.dailyGoalMinutes * 60
    },
    capabilities: {
      activeWindow: !isWayland,
      monitorTracking: true,
      waylandLimited: isWayland,
      platform: process.platform
    }
  };
}

function broadcast() {
  const payload = publicState();
  for (const window of [dashboardWindow, overlayWindow]) {
    if (window && !window.isDestroyed()) window.webContents.send('state:changed', payload);
  }
}

function scheduleSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => void saveState(), 300);
}

async function saveState() {
  if (!state || !dataFile) return;
  state.updatedAt = new Date().toISOString();
  const persisted = {
    version: state.version,
    updatedAt: state.updatedAt,
    settings: state.settings,
    history: state.history
  };
  const temporary = `${dataFile}.tmp`;
  await fs.mkdir(path.dirname(dataFile), { recursive: true });
  await fs.writeFile(temporary, JSON.stringify(persisted, null, 2));
  await fs.rename(temporary, dataFile);
}

function createDashboardWindow() {
  dashboardWindow = new BrowserWindow({
    width: 900,
    height: 780,
    minWidth: 720,
    minHeight: 520,
    transparent: true,
    backgroundColor: '#00000000',
    frame: false,
    title: 'No Focus Count',
    vibrancy: process.platform === 'darwin' ? 'under-window' : undefined,
    visualEffectState: process.platform === 'darwin' ? 'active' : undefined,
    webPreferences: {
      preload: path.join(ROOT, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });
  dashboardWindow.loadFile(path.join(ROOT, 'src', 'index.html'));
  if (isDevelopment) {
    dashboardWindow.webContents.on('did-fail-load', (_, code, description) => {
      console.error(`[renderer:load] ${code} ${description}`);
    });
  }
  dashboardWindow.webContents.once('did-finish-load', () => {
    const screenshotPath = process.env.NFC_SCREENSHOT_PATH;
    if (!screenshotPath) return;
    setTimeout(async () => {
      const image = await dashboardWindow.webContents.capturePage();
      await fs.writeFile(screenshotPath, image.toPNG());
    }, 1200);
  });
  dashboardWindow.on('closed', () => { dashboardWindow = undefined; });
  dashboardWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('https://')) void shell.openExternal(url);
    return { action: 'deny' };
  });
}

function createOverlayWindow() {
  overlayWindow = new BrowserWindow({
    width: 390,
    height: 180,
    transparent: true,
    backgroundColor: '#00000000',
    frame: false,
    resizable: false,
    maximizable: false,
    minimizable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    hasShadow: false,
    show: false,
    focusable: true,
    webPreferences: {
      preload: path.join(ROOT, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });
  overlayWindow.loadFile(path.join(ROOT, 'src', 'index.html'), { query: { overlay: '1' } });
  overlayWindow.webContents.once('did-finish-load', () => {
    const screenshotPath = process.env.NFC_OVERLAY_SCREENSHOT_PATH;
    if (!screenshotPath) return;
    showOverlay();
    setTimeout(async () => {
      const image = await overlayWindow.webContents.capturePage();
      await fs.writeFile(screenshotPath, image.toPNG());
    }, 1200);
  });
  overlayWindow.setAlwaysOnTop(true, process.platform === 'darwin' ? 'floating' : 'normal');
  overlayWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  setOverlayInteractive(false);
  overlayWindow.on('closed', () => { overlayWindow = undefined; });
}

function showOverlay() {
  if (!overlayWindow || overlayWindow.isDestroyed()) createOverlayWindow();
  const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  const [width, height] = overlayWindow.getSize();
  overlayWindow.setPosition(
    Math.round(display.workArea.x + display.workArea.width - width - 28),
    Math.round(display.workArea.y + 28)
  );
  overlayWindow.showInactive();
  setOverlayInteractive(false);
}

function setOverlayInteractive(interactive) {
  if (!overlayWindow || overlayWindow.isDestroyed()) return;
  try {
    overlayWindow.setIgnoreMouseEvents(!interactive, { forward: true });
  } catch {
    overlayWindow.setIgnoreMouseEvents(!interactive);
  }
}

function temporarilyUnlockOverlay() {
  showOverlay();
  setOverlayInteractive(true);
  overlayWindow.webContents.send('overlay:unlock', true);
  clearTimeout(overlayInteractiveTimer);
  overlayInteractiveTimer = setTimeout(() => {
    setOverlayInteractive(false);
    overlayWindow?.webContents.send('overlay:unlock', false);
  }, 8000);
}

function displaysForRenderer() {
  return screen.getAllDisplays().map((display, index) => ({
    id: String(display.id),
    label: display.label || `모니터 ${index + 1}`,
    bounds: display.bounds,
    workArea: display.workArea,
    scaleFactor: display.scaleFactor,
    primary: display.id === screen.getPrimaryDisplay().id
  }));
}

async function windowOptions() {
  try {
    const windows = await openWindows({
      accessibilityPermission: true,
      screenRecordingPermission: true
    });
    return windows
      .filter(window => window.owner?.processId !== process.pid)
      .map(window => ({
        id: String(window.id),
        title: window.title || '제목 없는 창',
        bounds: window.bounds,
        url: window.url,
        owner: window.owner
      }));
  } catch {
    return [];
  }
}

async function currentContext() {
  let active;
  if (!isWayland) {
    try {
      active = await activeWindow({
        accessibilityPermission: true,
        screenRecordingPermission: true
      });
    } catch {
      active = undefined;
    }
  }
  const displays = displaysForRenderer();
  const display = active?.bounds
    ? displayForBounds(displays, active.bounds)
    : screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  return {
    activeWindow: active ? {
      id: String(active.id),
      title: active.title || '',
      bounds: active.bounds,
      url: active.url,
      owner: active.owner
    } : undefined,
    activeDisplayId: String(display?.id ?? ''),
    capturedAt: new Date().toISOString()
  };
}

function closeCurrentEvent(at = new Date().toISOString()) {
  const session = state.runtime.currentSession;
  const index = state.runtime.currentEventIndex;
  if (!session || index == null || !session.events[index]) return;
  session.events[index].endedAt = at;
  state.runtime.currentEventIndex = null;
}

function recordDistraction(context, reason) {
  const session = state.runtime.currentSession;
  if (!session) return;
  const active = context.activeWindow;
  const identity = `${reason}|${active?.id ?? ''}|${context.activeDisplayId}`;
  const index = state.runtime.currentEventIndex;
  if (index != null && session.events[index]?.identity === identity) return;
  closeCurrentEvent(context.capturedAt);
  session.events.push({
    id: crypto.randomUUID(),
    identity,
    reason,
    startedAt: context.capturedAt,
    endedAt: null,
    displayId: context.activeDisplayId,
    appName: active?.owner?.name ?? (isWayland ? 'Wayland 모니터 이동' : '알 수 없는 앱'),
    windowTitle: active?.title ?? '',
    url: state.settings.recordUrls ? active?.url : undefined
  });
  state.runtime.currentEventIndex = session.events.length - 1;
}

async function tick() {
  if (tickBusy || !state?.runtime.currentSession) return;
  if (state.runtime.phase === 'paused-user') return;
  tickBusy = true;
  try {
    const session = state.runtime.currentSession;
    if (session.mode === 'break') {
      state.runtime.phase = 'break';
      session.focusedSeconds += 1;
      state.runtime.remainingSeconds = Math.max(0, state.runtime.remainingSeconds - 1);
    } else {
      const context = await currentContext();
      state.runtime.lastContext = context;
      const evaluation = evaluateFocus({
        activeWindow: context.activeWindow,
        activeDisplayId: context.activeDisplayId,
        targetWindow: session.targetWindow,
        targetDisplayId: session.targetDisplayId,
        windowLockEnabled: state.settings.windowLockEnabled && !isWayland,
        monitorLockEnabled: state.settings.monitorLockEnabled,
        tabLockEnabled: state.settings.tabLockEnabled && !isWayland,
        systemInactive: state.settings.pauseWhenScreenInactive && (
          systemPowerInactive || powerMonitor.getSystemIdleState(state.settings.idleThresholdSeconds) !== 'active'
        ),
        ownProcessId: process.pid
      });
      if (evaluation.focused) {
        closeCurrentEvent(context.capturedAt);
        state.runtime.phase = 'focusing';
        session.focusedSeconds += 1;
        state.runtime.remainingSeconds = Math.max(0, state.runtime.remainingSeconds - 1);
      } else {
        state.runtime.phase = 'paused-distraction';
        session.distractionSeconds += 1;
        recordDistraction(context, evaluation.reason);
      }
    }

    if (state.runtime.remainingSeconds <= 0) finishCurrentSession(true);
    scheduleSave();
    broadcast();
  } finally {
    tickBusy = false;
  }
}

function startSession(payload = {}) {
  const mode = payload.mode === 'break' ? 'break' : 'focus';
  const plannedSeconds = mode === 'focus'
    ? state.settings.focusMinutes * 60
    : nextBreakSeconds(state.runtime.completedCycles, state.settings);
  state.runtime.currentSession = {
    id: crypto.randomUUID(),
    participantName: String(payload.participantName || state.settings.participantName || '나').slice(0, 60),
    mode,
    startedAt: new Date().toISOString(),
    endedAt: null,
    plannedSeconds,
    focusedSeconds: 0,
    distractionSeconds: 0,
    completed: false,
    targetWindow: mode === 'focus' ? payload.targetWindow ?? null : null,
    targetDisplayId: mode === 'focus' ? payload.targetDisplayId ?? null : null,
    events: []
  };
  state.runtime.mode = mode;
  state.runtime.phase = mode === 'focus' ? 'focusing' : 'break';
  state.runtime.remainingSeconds = plannedSeconds;
  state.runtime.currentEventIndex = null;
  if (state.settings.autoOpenOverlay) showOverlay();
  scheduleSave();
  broadcast();
}

function finishCurrentSession(completed) {
  const session = state.runtime.currentSession;
  if (!session) return;
  closeCurrentEvent();
  session.endedAt = new Date().toISOString();
  session.completed = completed;
  if (session.focusedSeconds > 0 || session.distractionSeconds > 0) {
    state.history.unshift(session);
    state.history = state.history.slice(0, 1000);
  }

  if (session.mode === 'focus') {
    if (completed) state.runtime.completedCycles += 1;
    state.runtime.suggestedMode = 'break';
    state.runtime.remainingSeconds = nextBreakSeconds(state.runtime.completedCycles, state.settings);
  } else {
    state.runtime.suggestedMode = 'focus';
    state.runtime.remainingSeconds = state.settings.focusMinutes * 60;
  }
  state.runtime.mode = state.runtime.suggestedMode;
  state.runtime.phase = completed ? 'completed' : 'idle';
  state.runtime.currentSession = null;
  state.runtime.currentEventIndex = null;

  if (completed && state.settings.alarmEnabled) fireAlarm(session.mode);
  scheduleSave();
  broadcast();
}

function fireAlarm(mode) {
  shell.beep();
  const title = mode === 'focus' ? '집중 완료' : '휴식 완료';
  if (Notification.isSupported()) {
    new Notification({ title: `${title} ✦`, body: mode === 'focus' ? '이제 잠깐 쉬어가세요.' : '다음 집중을 시작할 시간입니다.' }).show();
  }
  if (process.platform === 'darwin') app.dock?.bounce('critical');
  dashboardWindow?.flashFrame(true);
}

function updateSettings(patch = {}) {
  const previousFocus = state.settings.focusMinutes;
  state.settings = mergeSettings({
    ...state.settings,
    ...patch,
    theme: { ...state.settings.theme, ...(patch.theme ?? {}) },
    sync: { ...state.settings.sync, ...(patch.sync ?? {}) }
  });
  if (!state.runtime.currentSession && previousFocus !== state.settings.focusMinutes && state.runtime.suggestedMode === 'focus') {
    state.runtime.remainingSeconds = state.settings.focusMinutes * 60;
  }
  scheduleSave();
  broadcast();
  return publicState();
}

function encodeToken(token) {
  if (!token) return '';
  return safeStorage.isEncryptionAvailable()
    ? safeStorage.encryptString(token).toString('base64')
    : Buffer.from(token).toString('base64');
}

function decodeToken() {
  const encoded = state.settings.sync.tokenEncrypted;
  if (!encoded) return '';
  const value = Buffer.from(encoded, 'base64');
  return safeStorage.isEncryptionAvailable()
    ? safeStorage.decryptString(value)
    : value.toString('utf8');
}

async function runSync(direction) {
  const { endpoint, accountId } = state.settings.sync;
  const token = decodeToken();
  if (!endpoint || !accountId || !token) throw new Error('동기화 주소, 계정 ID, 토큰이 필요합니다.');
  const url = `${endpoint.replace(/\/$/, '')}/state/${encodeURIComponent(accountId)}`;
  const headers = { authorization: `Bearer ${token}`, 'content-type': 'application/json' };

  if (direction === 'push') {
    const response = await fetch(url, {
      method: 'PUT',
      headers,
      body: JSON.stringify({
        version: state.version,
        updatedAt: state.updatedAt,
        settings: { ...state.settings, sync: undefined },
        history: state.history
      })
    });
    if (!response.ok) throw new Error(`업로드 실패 (${response.status})`);
  } else {
    const response = await fetch(url, { headers });
    if (!response.ok) throw new Error(`다운로드 실패 (${response.status})`);
    const remote = await response.json();
    const byId = new Map([...state.history, ...(remote.history ?? [])].map(session => [session.id, session]));
    state.history = [...byId.values()].sort((a, b) => new Date(b.startedAt) - new Date(a.startedAt));
    if (remote.settings) {
      state.settings = mergeSettings({
        ...remote.settings,
        sync: state.settings.sync
      });
    }
    scheduleSave();
    broadcast();
  }
  return { ok: true, at: new Date().toISOString() };
}

function registerIPC() {
  ipcMain.handle('state:get', () => publicState());
  ipcMain.handle('context:list', async () => ({ windows: await windowOptions(), displays: displaysForRenderer() }));
  ipcMain.handle('settings:update', (_, patch) => updateSettings(patch));
  ipcMain.handle('session:start', (_, payload) => startSession(payload));
  ipcMain.handle('session:pause-toggle', () => {
    if (!state.runtime.currentSession) return;
    state.runtime.phase = state.runtime.phase === 'paused-user'
      ? (state.runtime.mode === 'break' ? 'break' : 'focusing')
      : 'paused-user';
    broadcast();
  });
  ipcMain.handle('session:stop', () => finishCurrentSession(false));
  ipcMain.handle('overlay:show', () => showOverlay());
  ipcMain.handle('overlay:hide', () => overlayWindow?.hide());
  ipcMain.handle('overlay:set-interactive', (_, interactive) => setOverlayInteractive(Boolean(interactive)));
  ipcMain.handle('window:minimize', () => dashboardWindow?.minimize());
  ipcMain.handle('window:close', () => dashboardWindow?.close());
  ipcMain.handle('history:clear', () => {
    state.history = [];
    scheduleSave();
    broadcast();
  });
  ipcMain.handle('data:export', async () => {
    const result = await dialog.showSaveDialog(dashboardWindow, {
      defaultPath: `no-focus-count-${new Date().toISOString().slice(0, 10)}.json`,
      filters: [{ name: 'JSON', extensions: ['json'] }]
    });
    if (!result.canceled && result.filePath) {
      await fs.writeFile(result.filePath, JSON.stringify({ settings: state.settings, history: state.history }, null, 2));
    }
    return !result.canceled;
  });
  ipcMain.handle('data:import', async () => {
    const result = await dialog.showOpenDialog(dashboardWindow, { properties: ['openFile'], filters: [{ name: 'JSON', extensions: ['json'] }] });
    if (result.canceled || !result.filePaths[0]) return false;
    const imported = JSON.parse(await fs.readFile(result.filePaths[0], 'utf8'));
    const byId = new Map([...state.history, ...(imported.history ?? [])].map(session => [session.id, session]));
    state.history = [...byId.values()].sort((a, b) => new Date(b.startedAt) - new Date(a.startedAt));
    if (imported.settings) state.settings = mergeSettings({ ...state.settings, ...imported.settings, sync: state.settings.sync });
    scheduleSave();
    broadcast();
    return true;
  });
  ipcMain.handle('sync:configure', (_, config) => {
    const sync = { ...state.settings.sync, ...config };
    if (typeof config.token === 'string' && config.token.length > 0) sync.tokenEncrypted = encodeToken(config.token);
    delete sync.token;
    updateSettings({ sync });
    return publicState().settings.sync;
  });
  ipcMain.handle('sync:run', (_, direction) => runSync(direction));
}

app.whenReady().then(async () => {
  state = await loadState();
  registerIPC();
  createDashboardWindow();
  createOverlayWindow();
  globalShortcut.register('CommandOrControl+Shift+F', temporarilyUnlockOverlay);
  powerMonitor.on('lock-screen', () => { systemPowerInactive = true; });
  powerMonitor.on('suspend', () => { systemPowerInactive = true; });
  powerMonitor.on('unlock-screen', () => { systemPowerInactive = false; });
  powerMonitor.on('resume', () => { systemPowerInactive = false; });
  setInterval(() => void tick(), 1000);
  if (isDevelopment && process.env.NFC_DEVTOOLS === '1') {
    dashboardWindow.webContents.openDevTools({ mode: 'detach', activate: false });
  }

  app.on('activate', () => {
    if (!dashboardWindow || dashboardWindow.isDestroyed()) createDashboardWindow();
    dashboardWindow.show();
  });
});

app.on('before-quit', () => void saveState());
app.on('will-quit', () => globalShortcut.unregisterAll());
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
