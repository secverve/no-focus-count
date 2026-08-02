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
  theme: {
    timerColor: '#D7FF5F',
    accentColor: '#A7FF3F',
    panelColor: '#07100D',
    panelOpacity: 0.14,
    overlayOpacity: 0.04,
    blur: 18,
    timerSize: 104,
    overlayTimerSize: 72,
    shadowStrength: 0.9
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
  return {
    ...cloneDefaultSettings(),
    ...stored,
    theme: { ...cloneDefaultSettings().theme, ...(stored.theme ?? {}) },
    sync: { ...cloneDefaultSettings().sync, ...(stored.sync ?? {}) }
  };
}

export function formatTime(totalSeconds) {
  const seconds = Math.max(0, Math.round(Number(totalSeconds) || 0));
  return `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
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
  windowLockEnabled,
  monitorLockEnabled,
  tabLockEnabled,
  systemInactive,
  ownProcessId
}) {
  if (systemInactive) {
    return { focused: false, reason: 'screen-inactive' };
  }
  if (activeWindow?.owner?.processId === ownProcessId) {
    return { focused: true, reason: 'app-control' };
  }
  if (monitorLockEnabled && targetDisplayId != null && String(activeDisplayId) !== String(targetDisplayId)) {
    return { focused: false, reason: 'left-monitor' };
  }
  if (windowLockEnabled && targetWindow) {
    if (!activeWindow) return { focused: false, reason: 'window-unavailable' };
    if (String(activeWindow.id) !== String(targetWindow.id)) {
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
