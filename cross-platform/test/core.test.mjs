import test from 'node:test';
import assert from 'node:assert/strict';
import {
  aggregateFocusByDay,
  displayForBounds,
  evaluateFocus,
  focusScore,
  formatTime,
  mergeSettings,
  nextBreakSeconds
} from '../core.mjs';

test('formatTime renders a readable clock', () => {
  assert.equal(formatTime(1500), '25:00');
  assert.equal(formatTime(-3), '00:00');
});

test('displayForBounds selects the monitor containing the window center', () => {
  const displays = [
    { id: 1, bounds: { x: 0, y: 0, width: 1920, height: 1080 } },
    { id: 2, bounds: { x: 1920, y: 0, width: 1920, height: 1080 } }
  ];
  assert.equal(displayForBounds(displays, { x: 2200, y: 100, width: 800, height: 600 }).id, 2);
});

test('monitor lock catches leaving a selected monitor', () => {
  const result = evaluateFocus({
    activeWindow: { id: 10, owner: { processId: 8 } },
    activeDisplayId: 2,
    targetWindow: { id: 10 },
    targetDisplayId: 1,
    windowLockEnabled: true,
    monitorLockEnabled: true,
    ownProcessId: 999
  });
  assert.deepEqual(result, { focused: false, reason: 'left-monitor' });
});

test('focus score uses focused and distracted time', () => {
  assert.equal(focusScore({ focusedSeconds: 80, distractionSeconds: 20 }), 80);
});

test('same browser window with another tab pauses focus', () => {
  const result = evaluateFocus({
    activeWindow: { id: 10, title: 'Video', url: 'https://youtube.com/watch?v=2', owner: { processId: 8 } },
    activeDisplayId: 1,
    targetWindow: { id: 10, title: 'Lecture', url: 'https://example.com/lecture' },
    targetDisplayId: 1,
    windowLockEnabled: false,
    monitorLockEnabled: true,
    tabLockEnabled: true,
    systemInactive: false,
    ownProcessId: 999
  });
  assert.deepEqual(result, { focused: false, reason: 'different-tab' });
});

test('locked or sleeping screen pauses regardless of window', () => {
  const result = evaluateFocus({
    activeWindow: { id: 10, owner: { processId: 8 } },
    activeDisplayId: 1,
    targetWindow: { id: 10 },
    targetDisplayId: 1,
    windowLockEnabled: false,
    monitorLockEnabled: false,
    tabLockEnabled: false,
    systemInactive: true,
    ownProcessId: 999
  });
  assert.deepEqual(result, { focused: false, reason: 'screen-inactive' });
});

test('settings migration keeps new theme values', () => {
  const settings = mergeSettings({ theme: { timerColor: '#FFFFFF' } });
  assert.equal(settings.theme.timerColor, '#FFFFFF');
  assert.equal(typeof settings.theme.panelOpacity, 'number');
});

test('long break follows configured cycle interval', () => {
  const settings = { breakMinutes: 5, longBreakMinutes: 20, cyclesBeforeLongBreak: 4 };
  assert.equal(nextBreakSeconds(3, settings), 300);
  assert.equal(nextBreakSeconds(4, settings), 1200);
});

test('calendar aggregation totals focus sessions by local day', () => {
  const history = [
    { mode: 'focus', startedAt: '2026-08-02T01:00:00', focusedSeconds: 600, distractionSeconds: 30 },
    { mode: 'focus', startedAt: '2026-08-02T03:00:00', focusedSeconds: 900, distractionSeconds: 60 },
    { mode: 'break', startedAt: '2026-08-02T04:00:00', focusedSeconds: 300, distractionSeconds: 0 }
  ];
  assert.deepEqual(aggregateFocusByDay(history)['2026-08-02'], {
    focusSeconds: 1500,
    distractionSeconds: 90,
    sessions: 2
  });
});
