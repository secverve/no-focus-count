import test from 'node:test';
import assert from 'node:assert/strict';
import {
  applyTodoMutation,
  aggregateFocusByDay,
  boundedElapsedSeconds,
  displayForBounds,
  evaluateFocus,
  focusScore,
  formatTime,
  mergeSettings,
  nextBreakSeconds,
  normalizeTodos,
  reconcileFocusDuration
} from '../core.mjs';

test('formatTime renders a readable clock', () => {
  assert.equal(formatTime(1500), '25:00');
  assert.equal(formatTime(-3), '00:00');
});

test('elapsed measurement follows wall time without counting long stalls', () => {
  assert.equal(boundedElapsedSeconds(1_000, 2_250), 1.25);
  assert.equal(boundedElapsedSeconds(1_000, 9_000), 2);
  assert.equal(boundedElapsedSeconds(2_000, 1_000), 0);
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

test('a selected window stays locked even if the legacy toggle is off', () => {
  const result = evaluateFocus({
    activeWindow: { id: 88, title: 'Codex', owner: { processId: 20 } },
    activeDisplayId: 1,
    targetWindow: { id: 10, title: 'Chrome study', owner: { processId: 8 } },
    targetDisplayId: 1,
    windowLockEnabled: false,
    monitorLockEnabled: false,
    tabLockEnabled: false,
    systemInactive: false,
    ownProcessId: 999
  });
  assert.deepEqual(result, { focused: false, reason: 'different-window' });
});

test('opening No Focus Count does not count as Chrome focus', () => {
  const result = evaluateFocus({
    activeWindow: { id: 77, title: 'No Focus Count', owner: { processId: 999 } },
    activeDisplayId: 1,
    targetWindow: { id: 10, title: 'Chrome study', owner: { processId: 8 } },
    targetDisplayId: 1,
    windowLockEnabled: true,
    monitorLockEnabled: false,
    tabLockEnabled: false,
    systemInactive: false,
    ownProcessId: 999
  });
  assert.deepEqual(result, { focused: false, reason: 'different-window' });
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
  assert.equal(settings.theme.surfaceTransparency, 0);
  assert.equal(settings.theme.displayFont, 'rounded');
  assert.equal(settings.overlayPosition, null);
});

test('appearance settings preserve supported fonts and bound transparency', () => {
  const customized = mergeSettings({
    theme: { displayFont: 'mono', surfaceTransparency: 0.42 }
  });
  assert.equal(customized.theme.displayFont, 'mono');
  assert.equal(customized.theme.surfaceTransparency, 0.42);

  const invalid = mergeSettings({
    theme: { displayFont: 'url(https://example.com/font.woff2)', surfaceTransparency: 9 }
  });
  assert.equal(invalid.theme.displayFont, 'rounded');
  assert.equal(invalid.theme.surfaceTransparency, 0.8);
  assert.equal(mergeSettings({ theme: { surfaceTransparency: -1 } }).theme.surfaceTransparency, 0);
});

test('todo normalization keeps safe checklist goals and bounds stored data', () => {
  const todos = normalizeTodos([
    { id: 'morning', title: '  기획서 마무리  ', completed: true },
    { id: 'morning', title: '중복 ID' },
    { id: '<style>', title: '자료 검토' },
    { id: 'empty', title: '   ' }
  ]);
  assert.deepEqual(todos, [
    { id: 'morning', title: '기획서 마무리', completed: true },
    { id: 'todo-1', title: '중복 ID', completed: false },
    { id: 'todo-2', title: '자료 검토', completed: false }
  ]);
  assert.equal(normalizeTodos(Array.from({ length: 30 }, (_, index) => ({
    id: `goal-${index}`,
    title: `목표 ${index}`
  }))).length, 24);
});

test('focus duration is rounded and bounded at the settings boundary', () => {
  assert.equal(mergeSettings({ focusMinutes: 42.7 }).focusMinutes, 43);
  assert.equal(mergeSettings({ focusMinutes: -10 }).focusMinutes, 1);
  assert.equal(mergeSettings({ focusMinutes: 999 }).focusMinutes, 180);
  assert.equal(mergeSettings({ focusMinutes: 'invalid' }).focusMinutes, 25);
});

test('imported focus duration updates an idle focus countdown', () => {
  const runtime = { currentSession: null, suggestedMode: 'focus', remainingSeconds: 1500 };
  reconcileFocusDuration(runtime, 25, 45);
  assert.equal(runtime.remainingSeconds, 2700);
});

test('rapid todo completion mutations preserve both changes', () => {
  const initial = [
    { id: 'race-a', title: '첫 번째 목표', completed: false },
    { id: 'race-b', title: '두 번째 목표', completed: false }
  ];
  const first = applyTodoMutation(initial, { type: 'complete', id: 'race-a', completed: true });
  const second = applyTodoMutation(first, { type: 'complete', id: 'race-b', completed: true });
  assert.deepEqual(second.map(todo => todo.completed), [true, true]);
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
