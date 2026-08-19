const DISPLAY_FONT_KEYS = new Set(['rounded', 'sans', 'mono', 'serif']);
const MAX_SURFACE_TRANSPARENCY = 0.8;
const MAX_TODOS = 24;
const MAX_TODO_TITLE_LENGTH = 80;
const MAX_FOCUS_MINUTES = 180;

export const DEFAULT_SETTINGS = Object.freeze({
  participantName: '나',
  focusMinutes: 25,
  breakMinutes: 5,
  longBreakMinutes: 15,
  cyclesBeforeLongBreak: 4,
  dailyGoalMinutes: 120,
  windowLockEnabled: true,
  monitorLockEnabled: true,
  tabLockEnabled: true,
  pauseWhenScreenInactive: true,
  idleThresholdSeconds: 120,
  recordUrls: false,
  alarmEnabled: true,
  autoOpenOverlay: true,
  overlayPosition: null,
  theme: {
    timerColor: '#D7FF5F',
    accentColor: '#A7FF3F',
    panelColor: '#07100D',
    panelOpacity: 0.14,
    overlayOpacity: 0.04,
    blur: 18,
    timerSize: 104,
    overlayTimerSize: 72,
    shadowStrength: 0.9,
    surfaceTransparency: 0,
    displayFont: 'rounded'
  },
  sync: {
    endpoint: '',
    accountId: '',
    enabled: false,
    tokenEncrypted: ''
  }
});

export function cloneDefaultSettings() {
  return structuredClone(DEFAULT_SETTINGS);
}

export function mergeSettings(stored = {}) {
  const defaults = cloneDefaultSettings();
  const theme = { ...defaults.theme, ...(stored.theme ?? {}) };
  const surfaceTransparency = Number(theme.surfaceTransparency);
  const focusMinutes = Number(stored.focusMinutes);
  return {
    ...defaults,
    ...stored,
    focusMinutes: Number.isFinite(focusMinutes)
      ? Math.min(MAX_FOCUS_MINUTES, Math.max(1, Math.round(focusMinutes)))
      : defaults.focusMinutes,
    theme: {
      ...theme,
      surfaceTransparency: Number.isFinite(surfaceTransparency)
        ? Math.min(MAX_SURFACE_TRANSPARENCY, Math.max(0, surfaceTransparency))
        : defaults.theme.surfaceTransparency,
      displayFont: DISPLAY_FONT_KEYS.has(theme.displayFont)
        ? theme.displayFont
        : defaults.theme.displayFont
    },
    sync: { ...defaults.sync, ...(stored.sync ?? {}) }
  };
}

export function normalizeTodos(todos) {
  if (!Array.isArray(todos)) return [];
  const normalized = [];
  const usedIds = new Set();

  for (const [index, todo] of todos.entries()) {
    if (normalized.length >= MAX_TODOS) break;
    if (!todo || typeof todo !== 'object' || Array.isArray(todo)) continue;
    const title = String(todo.title ?? '').trim().slice(0, MAX_TODO_TITLE_LENGTH);
    if (!title) continue;

    let id = typeof todo.id === 'string' ? todo.id.trim().slice(0, 80) : '';
    if (!/^[A-Za-z0-9_-]+$/.test(id) || usedIds.has(id)) {
      id = `todo-${index}`;
      while (usedIds.has(id)) id += '-copy';
    }
    usedIds.add(id);

    normalized.push({
      id,
      title,
      completed: todo.completed === true
    });
  }
  return normalized;
}

export function applyTodoMutation(todos, mutation) {
  const current = normalizeTodos(todos);
  if (!mutation || typeof mutation !== 'object' || Array.isArray(mutation)) return current;
  if (mutation.type === 'add') return normalizeTodos([...current, mutation.todo]);
  if (mutation.type === 'complete') {
    return current.map(todo => (
      todo.id === mutation.id ? { ...todo, completed: mutation.completed === true } : todo
    ));
  }
  if (mutation.type === 'remove') return current.filter(todo => todo.id !== mutation.id);
  return current;
}

export function reconcileFocusDuration(runtime, previousFocusMinutes, nextFocusMinutes) {
  if (!runtime.currentSession && previousFocusMinutes !== nextFocusMinutes && runtime.suggestedMode === 'focus') {
    runtime.remainingSeconds = nextFocusMinutes * 60;
  }
}

export function formatTime(totalSeconds) {
  const seconds = Math.max(0, Math.round(Number(totalSeconds) || 0));
  return `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
}

export function boundedElapsedSeconds(previousMilliseconds, currentMilliseconds, maximumSeconds = 2) {
  const previous = Number(previousMilliseconds);
  const current = Number(currentMilliseconds);
  if (!Number.isFinite(previous) || !Number.isFinite(current)) return 0;
  return Math.min(Math.max(0, Number(maximumSeconds) || 0), Math.max(0, (current - previous) / 1000));
}

export function displayForBounds(displays, bounds) {
  if (!Array.isArray(displays) || displays.length === 0 || !bounds) return undefined;
  const center = {
    x: bounds.x + bounds.width / 2,
    y: bounds.y + bounds.height / 2
  };
  return displays.find(({ bounds: area }) => (
    center.x >= area.x && center.x < area.x + area.width &&
    center.y >= area.y && center.y < area.y + area.height
  )) ?? displays[0];
}

export function evaluateFocus({
  activeWindow,
  activeDisplayId,
  targetWindow,
  targetDisplayId,
  monitorLockEnabled,
  tabLockEnabled,
  systemInactive
}) {
  if (systemInactive) {
    return { focused: false, reason: 'screen-inactive' };
  }
  if (monitorLockEnabled && targetDisplayId != null && String(activeDisplayId) !== String(targetDisplayId)) {
    return { focused: false, reason: 'left-monitor' };
  }
  if (targetWindow) {
    if (!activeWindow) return { focused: false, reason: 'window-unavailable' };
    const activeOwner = activeWindow.owner?.processId;
    const targetOwner = targetWindow.owner?.processId;
    if ((activeOwner != null && targetOwner != null && String(activeOwner) !== String(targetOwner))
      || String(activeWindow.id) !== String(targetWindow.id)) {
      return { focused: false, reason: 'different-window' };
    }
  }
  if (tabLockEnabled && targetWindow && activeWindow) {
    if (targetWindow.url && activeWindow.url && targetWindow.url !== activeWindow.url) {
      return { focused: false, reason: 'different-tab' };
    }
    if (!targetWindow.url && targetWindow.title && activeWindow.title && targetWindow.title !== activeWindow.title) {
      return { focused: false, reason: 'different-tab' };
    }
  }
  return { focused: true, reason: 'focused' };
}

export function focusScore(session) {
  const focused = Number(session?.focusedSeconds) || 0;
  const distracted = Number(session?.distractionSeconds) || 0;
  const total = focused + distracted;
  return total > 0 ? Math.round((focused / total) * 100) : 0;
}

export function localDateKey(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function todayFocusSeconds(history, date = new Date()) {
  const key = localDateKey(date);
  return (history ?? [])
    .filter(session => localDateKey(new Date(session.startedAt)) === key && session.mode === 'focus')
    .reduce((sum, session) => sum + (Number(session.focusedSeconds) || 0), 0);
}

export function aggregateFocusByDay(history) {
  const days = new Map();
  for (const session of history ?? []) {
    if (session.mode !== 'focus' || !session.startedAt) continue;
    const key = localDateKey(new Date(session.startedAt));
    const current = days.get(key) ?? { focusSeconds: 0, distractionSeconds: 0, sessions: 0 };
    current.focusSeconds += Number(session.focusedSeconds) || 0;
    current.distractionSeconds += Number(session.distractionSeconds) || 0;
    current.sessions += 1;
    days.set(key, current);
  }
  return Object.fromEntries(days);
}

export function nextBreakSeconds(completedCycles, settings) {
  const longBreak = completedCycles > 0 && completedCycles % settings.cyclesBeforeLongBreak === 0;
  return (longBreak ? settings.longBreakMinutes : settings.breakMinutes) * 60;
}
