const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const isOverlay = new URLSearchParams(location.search).get('overlay') === '1';

let state;
let context = { windows: [], displays: [] };
let selectedMode = 'focus';
let calendarCursor = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
let switcherDisplayId = null;
let switcherWindowId = null;

const reasonLabels = {
  ready: '준비',
  checking: '창 확인 중',
  focused: '집중 측정 중',
  'app-control': '앱 설정 조작 중',
  'left-monitor': '선택 모니터 이탈',
  'different-window': '다른 창 사용',
  'different-tab': '브라우저 탭 변경',
  'screen-inactive': '화면 잠금·절전·유휴',
  'window-unavailable': '집중 창 닫힘/숨김',
  break: '휴식 측정 중',
  completed: '완료'
};

const formatTime = value => {
  const seconds = Math.max(0, Math.round(Number(value) || 0));
  return `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
};

const formatKoreanDuration = value => {
  const seconds = Math.max(0, Math.round(Number(value) || 0));
  if (seconds < 60) return `${seconds}초`;
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  if (minutes < 60) return remainder ? `${minutes}분 ${remainder}초` : `${minutes}분`;
  const hours = Math.floor(minutes / 60);
  const minuteRemainder = minutes % 60;
  return minuteRemainder ? `${hours}시간 ${minuteRemainder}분` : `${hours}시간`;
};

const phaseLabel = phase => ({
  idle: 'READY',
  focusing: 'FOCUSING',
  break: 'BREAK',
  'paused-user': 'PAUSED',
  'paused-distraction': 'DISTRACTED',
  completed: 'COMPLETE'
}[phase] ?? phase.toUpperCase());

function applyTheme(theme) {
  const root = document.documentElement;
  root.style.setProperty('--timer', theme.timerColor);
  root.style.setProperty('--accent', theme.accentColor);
  root.style.setProperty('--panel', theme.panelColor);
  root.style.setProperty('--panel-opacity', theme.panelOpacity);
  root.style.setProperty('--overlay-opacity', theme.overlayOpacity);
  root.style.setProperty('--overlay-glass', `${Math.round(Math.min(0.62, Math.max(0.14, Number(theme.overlayOpacity) + 0.18)) * 100)}%`);
  root.style.setProperty('--blur', `${theme.blur}px`);
  root.style.setProperty('--timer-size', `${theme.timerSize}px`);
  root.style.setProperty('--overlay-timer-size', `${theme.overlayTimerSize}px`);
  root.style.setProperty('--shadow', theme.shadowStrength);
}

function renderOverlay() {
  applyTheme(state.settings.theme);
  $('#overlay-time').textContent = formatTime(state.runtime.remainingSeconds);
  $('#overlay-mode').textContent = state.runtime.mode === 'break' ? 'BREAK' : 'FOCUS';
  $('#overlay-status span').textContent = phaseLabel(state.runtime.phase);
  const target = state.runtime.currentSession?.targetWindow;
  const targetTitle = target?.title || (target ? `창 #${target.id}` : '집중 창 미선택');
  $('#overlay-target').textContent = target ? `${target.owner?.name ?? '앱'} · ${targetTitle}` : targetTitle;
  $('#overlay-target').title = $('#overlay-target').textContent;
  $('#overlay-pause').textContent = state.runtime.phase === 'paused-user' ? '▶' : 'Ⅱ';
  $('#overlay-stop').style.display = state.runtime.currentSession ? '' : 'none';
}

function setValue(id, value) {
  const element = $(id);
  if (element && document.activeElement !== element) element.value = value;
}

function renderDashboard() {
  applyTheme(state.settings.theme);
  const runtime = state.runtime;
  const session = runtime.currentSession ?? state.history[0];
  selectedMode = runtime.currentSession?.mode ?? selectedMode ?? runtime.suggestedMode;

  $('#timer-number').textContent = formatTime(runtime.remainingSeconds);
  $('#phase-line span').textContent = phaseLabel(runtime.phase);
  $$('.mode-switch button').forEach(button => button.classList.toggle('active', button.dataset.mode === selectedMode));
  $('#primary-action').textContent = runtime.currentSession
    ? (runtime.phase === 'paused-user' ? 'RESUME' : 'PAUSE')
    : (selectedMode === 'break' ? 'START BREAK' : 'START FOCUS');
  $('#stop-action').style.display = runtime.currentSession ? '' : 'none';

  const todayMinutes = Math.floor(state.analytics.todayFocusSeconds / 60);
  const goalMinutes = Math.round(state.analytics.dailyGoalSeconds / 60);
  $('#today-focus').textContent = `${todayMinutes}분`;
  $('#daily-goal').textContent = `${goalMinutes}분`;
  $('#goal-progress').style.width = `${Math.min(100, (state.analytics.todayFocusSeconds / Math.max(1, state.analytics.dailyGoalSeconds)) * 100)}%`;

  $('#metric-focused').textContent = formatTime(session?.focusedSeconds ?? 0);
  $('#metric-distractions').textContent = String(session?.events?.length ?? 0);
  $('#metric-lost').textContent = formatTime(session?.distractionSeconds ?? 0);
  $('#metric-cycles').textContent = String(runtime.completedCycles);
  $('#wayland-warning').hidden = !state.capabilities.waylandLimited;
  renderFocusInspector();

  const settings = state.settings;
  setValue('#participant-name', settings.participantName);
  setValue('#focus-minutes', settings.focusMinutes);
  setValue('#break-minutes', settings.breakMinutes);
  setValue('#long-break-minutes', settings.longBreakMinutes);
  setValue('#long-break-cycle', settings.cyclesBeforeLongBreak);
  setValue('#daily-goal-minutes', settings.dailyGoalMinutes);
  setValue('#idle-threshold', settings.idleThresholdSeconds);
  $('#window-lock').checked = true;
  $('#monitor-lock').checked = settings.monitorLockEnabled;
  $('#tab-lock').checked = settings.tabLockEnabled;
  $('#screen-inactive').checked = settings.pauseWhenScreenInactive;
  $('#record-urls').checked = settings.recordUrls;
  $('#alarm-enabled').checked = settings.alarmEnabled;
  $('#auto-overlay').checked = settings.autoOpenOverlay;

  setValue('#timer-color', settings.theme.timerColor);
  setValue('#accent-color', settings.theme.accentColor);
  setValue('#panel-color', settings.theme.panelColor);
  setRange('#panel-opacity', settings.theme.panelOpacity, `${Math.round(settings.theme.panelOpacity * 100)}%`);
  setRange('#overlay-opacity', settings.theme.overlayOpacity, `${Math.round(settings.theme.overlayOpacity * 100)}%`);
  setRange('#theme-blur', settings.theme.blur, `${settings.theme.blur}px`);
  setRange('#timer-size', settings.theme.timerSize, `${settings.theme.timerSize}px`);
  setRange('#shadow-strength', settings.theme.shadowStrength, Number(settings.theme.shadowStrength).toFixed(2));

  setValue('#sync-endpoint', settings.sync.endpoint ?? '');
  setValue('#sync-account', settings.sync.accountId ?? '');
  $('#sync-token').placeholder = settings.sync.hasToken ? '토큰 저장됨' : '접근 토큰';
  renderHistory();
  renderCalendar();
}

function setRange(selector, value, output) {
  const element = $(selector);
  if (document.activeElement !== element) element.value = value;
  element.closest('label').querySelector('output').textContent = output;
}

function renderHistory() {
  const focusSessions = state.history.filter(session => session.mode === 'focus');
  const participants = new Map();
  for (const session of focusSessions) {
    const name = session.participantName || '나';
    const row = participants.get(name) ?? { name, focusedSeconds: 0, distractionSeconds: 0, sessions: 0 };
    row.focusedSeconds += Number(session.focusedSeconds) || 0;
    row.distractionSeconds += Number(session.distractionSeconds) || 0;
    row.sessions += 1;
    participants.set(name, row);
  }
  const ranking = [...participants.values()].map(row => ({
    ...row,
    score: Math.round((row.focusedSeconds / Math.max(1, row.focusedSeconds + row.distractionSeconds)) * 100)
  })).sort((a, b) => b.score - a.score || b.focusedSeconds - a.focusedSeconds);
  const best = ranking[0];
  const worst = ranking.at(-1);
  $('#best-name').textContent = best?.name ?? '-';
  $('#best-score').textContent = best ? `${best.score}% · ${Math.round(best.focusedSeconds / 60)}분` : '기록 없음';
  $('#worst-name').textContent = worst?.name ?? '-';
  $('#worst-score').textContent = worst ? `${worst.score}% · 이탈 ${Math.round(worst.distractionSeconds / 60)}분` : '기록 없음';
  $('#focus-nudge').textContent = !worst
    ? '첫 집중 세션을 시작해 보세요.'
    : worst.score < 40
      ? '오늘은 알림과 방해 탭을 줄이고 짧은 세션부터 다시 시작해 봐요.'
      : worst.score < 70
        ? '조금 흔들렸지만 괜찮아요. 다음 한 세션만 더 또렷하게.'
        : '좋은 리듬이에요. 다음 휴식도 꼭 챙기세요.';

  $('#history-count').textContent = `${state.history.length} sessions`;
  $('#history-list').replaceChildren(...state.history.slice(0, 100).map(session => {
    const total = (session.focusedSeconds ?? 0) + (session.distractionSeconds ?? 0);
    const score = total > 0 ? Math.round((session.focusedSeconds / total) * 100) : 0;
    const item = document.createElement('details');
    item.className = 'history-item';
    const summary = document.createElement('summary');
    const copy = document.createElement('div');
    const title = document.createElement('strong');
    title.textContent = `${session.participantName || '나'} · ${session.mode === 'break' ? '휴식' : '집중'} ${formatTime(session.focusedSeconds)}`;
    const detail = document.createElement('small');
    detail.textContent = `${new Date(session.startedAt).toLocaleString()} · 이탈 ${session.events?.length ?? 0}회 · 손실 ${formatTime(session.distractionSeconds)}`;
    copy.append(title, detail);
    const badge = document.createElement('span');
    badge.className = 'history-score';
    badge.textContent = session.mode === 'focus' ? `${score}%` : 'REST';
    summary.append(copy, badge);
    item.append(summary);
    const events = document.createElement('div');
    events.className = 'event-list';
    const narrative = document.createElement('p');
    narrative.className = 'history-narrative';
    if (!session.events?.length) {
      narrative.textContent = '이 세션에서는 다른 창으로 가지 않고 집중을 마쳤습니다.';
      item.append(narrative);
      const empty = document.createElement('p');
      empty.textContent = '이탈 기록 없음';
      events.append(empty);
    } else {
      const movements = session.events.slice(0, 5).map(event => {
        const end = event.endedAt ? new Date(event.endedAt) : new Date();
        const duration = Math.max(0, Math.round((end - new Date(event.startedAt)) / 1000));
        return `${event.appName || '알 수 없는 앱'} · ${event.windowTitle || '제목 없음'}에서 ${formatKoreanDuration(duration)}`;
      });
      const remainder = session.events.length > 5 ? ` 외 ${session.events.length - 5}곳` : '';
      narrative.textContent = `잘 집중하시다가 ${movements.join(' → ')}${remainder} 이동했습니다.`;
      item.append(narrative);
      for (const event of session.events) {
        const row = document.createElement('p');
        const end = event.endedAt ? new Date(event.endedAt) : new Date();
        const duration = Math.max(0, Math.round((end - new Date(event.startedAt)) / 1000));
        const copyText = document.createElement('span');
        copyText.textContent = `${new Date(event.startedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} → ${event.appName || '알 수 없는 앱'} · ${event.windowTitle || '제목 없음'} · ${formatKoreanDuration(duration)} · ${reasonLabels[event.reason] ?? event.reason}`;
        row.append(copyText);
        if (event.url) {
          const url = document.createElement('small');
          url.textContent = event.url;
          row.append(url);
        }
        events.append(row);
      }
    }
    item.append(events);
    return item;
  }));
}

function displayForWindow(windowInfo) {
  if (!windowInfo?.bounds) return undefined;
  const centerX = windowInfo.bounds.x + windowInfo.bounds.width / 2;
  const centerY = windowInfo.bounds.y + windowInfo.bounds.height / 2;
  return context.displays.find(display => (
    centerX >= display.bounds.x && centerX < display.bounds.x + display.bounds.width &&
    centerY >= display.bounds.y && centerY < display.bounds.y + display.bounds.height
  ));
}

function windowIdentity(windowInfo) {
  if (!windowInfo) return '선택 없음';
  return `${windowInfo.owner?.name ?? '앱'} · 창 #${windowInfo.id}`;
}

function windowDetail(windowInfo, displayId) {
  if (!windowInfo) return '창을 선택하면 상세 정보가 표시됩니다';
  const display = displayForWindow(windowInfo) ?? context.displays.find(item => String(item.id) === String(displayId));
  return `${windowInfo.title || '제목 없음'} · ${display?.label ?? `모니터 ${displayId || '?'}`}`;
}

function updateSelectedWindowLabel() {
  const windowInfo = context.windows.find(item => String(item.id) === String($('#target-window').value));
  const label = $('#selected-window-label');
  label.textContent = windowInfo
    ? `${windowInfo.owner?.name ?? '앱'} · ${windowInfo.title || `창 #${windowInfo.id}`}`
    : '집중 창을 선택하세요';
}

function switcherWindows() {
  return context.windows.filter(windowInfo => {
    const display = displayForWindow(windowInfo);
    return display && String(display.id) === String(switcherDisplayId);
  });
}

function renderWindowSwitcher() {
  const displays = $('#switcher-displays');
  displays.replaceChildren(...context.displays.map(display => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `switcher-display${String(display.id) === String(switcherDisplayId) ? ' selected' : ''}`;
    const title = document.createElement('strong');
    title.textContent = `${display.label}${display.primary ? ' · 메인' : ''}`;
    const detail = document.createElement('small');
    const count = context.windows.filter(windowInfo => String(displayForWindow(windowInfo)?.id) === String(display.id)).length;
    detail.textContent = `${display.bounds.width}×${display.bounds.height} · 창 ${count}개`;
    button.append(title, detail);
    button.addEventListener('click', () => {
      switcherDisplayId = String(display.id);
      switcherWindowId = switcherWindows()[0]?.id ?? null;
      renderWindowSwitcher();
    });
    return button;
  }));

  const candidates = switcherWindows();
  if (!candidates.some(item => String(item.id) === String(switcherWindowId))) {
    switcherWindowId = candidates[0]?.id ?? null;
  }
  const container = $('#switcher-windows');
  if (!candidates.length) {
    const empty = document.createElement('p');
    empty.className = 'switcher-empty';
    empty.textContent = '이 모니터에서 선택할 창이 없습니다. 창을 옮긴 뒤 새로고침해 주세요.';
    container.replaceChildren(empty);
  } else {
    container.replaceChildren(...candidates.map(windowInfo => {
      const selected = String(windowInfo.id) === String(switcherWindowId);
      const card = document.createElement('button');
      card.type = 'button';
      card.className = `switcher-window${selected ? ' selected' : ''}`;
      card.dataset.windowId = String(windowInfo.id);
      const preview = document.createElement('div');
      preview.className = 'switcher-window-preview';
      const initial = document.createElement('b');
      initial.textContent = Array.from(windowInfo.owner?.name || '앱')[0]?.toUpperCase() || '앱';
      preview.append(initial);
      const copy = document.createElement('div');
      copy.className = 'switcher-window-copy';
      const appName = document.createElement('strong');
      appName.textContent = windowInfo.owner?.name ?? '알 수 없는 앱';
      const id = document.createElement('small');
      id.textContent = `창 #${windowInfo.id}`;
      const title = document.createElement('span');
      title.textContent = windowInfo.title || '제목 없는 창';
      copy.append(appName, id, title);
      card.append(preview, copy);
      card.addEventListener('click', () => {
        switcherWindowId = windowInfo.id;
        renderWindowSwitcher();
      });
      card.addEventListener('dblclick', confirmWindowSwitcher);
      return card;
    }));
    requestAnimationFrame(() => container.querySelector('.switcher-window.selected')?.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' }));
  }
  $('#switcher-confirm').disabled = !switcherWindowId;
}

async function openWindowSwitcher() {
  await refreshContext();
  switcherDisplayId = $('#target-display').value
    || String(context.displays.find(item => item.primary)?.id ?? context.displays[0]?.id ?? '');
  const currentWindowId = $('#target-window').value;
  switcherWindowId = switcherWindows().some(item => String(item.id) === String(currentWindowId))
    ? currentWindowId
    : switcherWindows()[0]?.id ?? null;
  renderWindowSwitcher();
  $('#window-switcher').showModal();
}

function stepWindowSwitcher(delta) {
  const candidates = switcherWindows();
  if (!candidates.length) return;
  const index = candidates.findIndex(item => String(item.id) === String(switcherWindowId));
  switcherWindowId = candidates[(Math.max(0, index) + delta + candidates.length) % candidates.length].id;
  renderWindowSwitcher();
}

function confirmWindowSwitcher() {
  const selected = context.windows.find(item => String(item.id) === String(switcherWindowId));
  if (!selected) return;
  $('#target-window').value = String(selected.id);
  $('#target-display').value = String(switcherDisplayId);
  updateSelectedWindowLabel();
  renderFocusInspector();
  $('#window-switcher').close();
}

function renderFocusInspector() {
  const runtime = state.runtime;
  const selectedId = $('#target-window')?.value;
  const target = runtime.currentSession?.targetWindow ?? context.windows.find(item => item.id === selectedId);
  const targetDisplayId = runtime.currentSession?.targetDisplayId ?? $('#target-display')?.value;
  const active = runtime.lastContext?.activeWindow;
  const activeDisplayId = runtime.lastContext?.activeDisplayId;
  const reason = runtime.lastFocusReason ?? 'ready';

  $('#inspector-target').textContent = windowIdentity(target);
  $('#inspector-target-detail').textContent = windowDetail(target, targetDisplayId);
  $('#inspector-active').textContent = active ? windowIdentity(active) : '측정 대기';
  $('#inspector-active-detail').textContent = active ? windowDetail(active, activeDisplayId) : '세션 중 1초마다 갱신됩니다';
  $('#inspector-verdict').textContent = reasonLabels[reason] ?? reason;
  $('#inspector-verdict-detail').textContent = `창 #${target?.id ?? '?'} · 모니터 ${targetDisplayId || '?'} 기준`;
  $('.focus-inspector article:last-child').classList.toggle('warn', !['ready', 'checking', 'focused', 'break', 'completed'].includes(reason));
}

function dateKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

function focusByDay() {
  const result = {};
  for (const session of state.history) {
    if (session.mode !== 'focus') continue;
    const key = dateKey(new Date(session.startedAt));
    result[key] ??= { focusSeconds: 0, distractionSeconds: 0, sessions: 0 };
    result[key].focusSeconds += Number(session.focusedSeconds) || 0;
    result[key].distractionSeconds += Number(session.distractionSeconds) || 0;
    result[key].sessions += 1;
  }
  return result;
}

function renderCalendar() {
  const year = calendarCursor.getFullYear();
  const month = calendarCursor.getMonth();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const leading = new Date(year, month, 1).getDay();
  const data = focusByDay();
  const goal = Math.max(60, state.settings.dailyGoalMinutes * 60);
  const cells = [];
  const monthRows = [];

  for (let index = 0; index < leading; index += 1) {
    const empty = document.createElement('div');
    empty.className = 'calendar-day empty';
    cells.push(empty);
  }
  for (let day = 1; day <= daysInMonth; day += 1) {
    const date = new Date(year, month, day);
    const key = dateKey(date);
    const entry = data[key] ?? { focusSeconds: 0, distractionSeconds: 0, sessions: 0 };
    if (entry.focusSeconds > 0) monthRows.push({ day, ...entry });
    const cell = document.createElement('div');
    cell.className = `calendar-day${key === dateKey(new Date()) ? ' today' : ''}`;
    cell.style.setProperty('--heat', Math.min(1, entry.focusSeconds / goal));
    cell.title = `${key} · 집중 ${Math.round(entry.focusSeconds / 60)}분 · ${entry.sessions}세션`;
    const number = document.createElement('b');
    number.textContent = String(day);
    const minutes = document.createElement('strong');
    minutes.textContent = entry.focusSeconds > 0 ? `${Math.round(entry.focusSeconds / 60)}분` : '·';
    const sessions = document.createElement('small');
    sessions.textContent = entry.sessions > 0 ? `${entry.sessions} sessions` : '';
    cell.append(number, minutes, sessions);
    cells.push(cell);
  }
  $('#focus-calendar').replaceChildren(...cells);
  $('#calendar-month').textContent = `${year}. ${String(month + 1).padStart(2, '0')}`;
  const total = monthRows.reduce((sum, row) => sum + row.focusSeconds, 0);
  const best = monthRows.toSorted((a, b) => b.focusSeconds - a.focusSeconds)[0];
  $('#month-total').textContent = `${Math.round(total / 60)}분`;
  $('#month-best').textContent = best ? `${best.day}일 · ${Math.round(best.focusSeconds / 60)}분` : '-';
  $('#month-days').textContent = `${monthRows.length}일`;
}

async function refreshContext() {
  context = await window.nfc.listContext();
  const windowSelect = $('#target-window');
  const displaySelect = $('#target-display');
  const oldWindow = windowSelect.value;
  const oldDisplay = displaySelect.value;

  windowSelect.replaceChildren(new Option('창을 선택하세요', ''), ...context.windows.map(item => {
    const display = displayForWindow(item);
    return new Option(`${item.owner?.name ?? '앱'} — ${item.title || '제목 없음'} · 창 #${item.id} · ${display?.label ?? '모니터 미확인'}`, item.id);
  }));
  displaySelect.replaceChildren(new Option('모니터를 선택하세요', ''), ...context.displays.map(item => new Option(`${item.label}${item.primary ? ' · 주 모니터' : ''} · ${item.bounds.width}×${item.bounds.height}`, item.id)));
  if (context.windows.some(item => item.id === oldWindow)) windowSelect.value = oldWindow;
  else windowSelect.value = '';
  if (context.displays.some(item => item.id === oldDisplay)) displaySelect.value = oldDisplay;
  else if (context.displays[0]) displaySelect.value = context.displays.find(item => item.primary)?.id ?? context.displays[0].id;
  updateSelectedWindowLabel();
  renderFocusInspector();
}

async function startOrToggle() {
  if (state.runtime.currentSession) {
    await window.nfc.togglePause();
    return;
  }
  const targetWindow = context.windows.find(item => item.id === $('#target-window').value);
  const targetDisplayId = $('#target-display').value || null;
  if (selectedMode === 'focus' && !targetWindow && !state.capabilities.waylandLimited) {
    await openWindowSwitcher();
    return;
  }
  await window.nfc.startSession({
    mode: selectedMode,
    participantName: $('#participant-name').value,
    targetWindow,
    targetDisplayId
  });
}

function bindDashboard() {
  $('#show-overlay').addEventListener('click', window.nfc.showOverlay);
  $('#timer-overlay-action').addEventListener('click', window.nfc.showOverlay);
  $('#minimize-window').addEventListener('click', window.nfc.minimize);
  $('#close-window').addEventListener('click', window.nfc.close);
  $('#primary-action').addEventListener('click', startOrToggle);
  $('#stop-action').addEventListener('click', window.nfc.stopSession);
  $('#refresh-context').addEventListener('click', refreshContext);
  $('#open-window-switcher').addEventListener('click', openWindowSwitcher);
  $('#target-window').addEventListener('change', () => {
    updateSelectedWindowLabel();
    renderFocusInspector();
  });
  $('#target-display').addEventListener('change', () => {
    const target = context.windows.find(item => String(item.id) === String($('#target-window').value));
    if (target && String(displayForWindow(target)?.id) !== String($('#target-display').value)) {
      $('#target-window').value = '';
      updateSelectedWindowLabel();
    }
    renderFocusInspector();
  });
  $('#switcher-close').addEventListener('click', () => $('#window-switcher').close());
  $('#switcher-refresh').addEventListener('click', async () => {
    await refreshContext();
    renderWindowSwitcher();
  });
  $('#switcher-confirm').addEventListener('click', confirmWindowSwitcher);
  $('#window-switcher').addEventListener('keydown', event => {
    if (event.key === 'Tab' || event.key === 'ArrowRight') {
      event.preventDefault();
      stepWindowSwitcher(event.shiftKey ? -1 : 1);
    } else if (event.key === 'ArrowLeft') {
      event.preventDefault();
      stepWindowSwitcher(-1);
    } else if (event.key === 'Enter') {
      event.preventDefault();
      confirmWindowSwitcher();
    }
  });

  $$('.mode-switch button').forEach(button => button.addEventListener('click', () => {
    if (state.runtime.currentSession) return;
    selectedMode = button.dataset.mode;
    $$('.mode-switch button').forEach(item => item.classList.toggle('active', item === button));
    state.runtime.remainingSeconds = selectedMode === 'focus'
      ? state.settings.focusMinutes * 60
      : state.settings.breakMinutes * 60;
    renderDashboard();
  }));

  $$('.tabs button').forEach(button => button.addEventListener('click', () => {
    $$('.tabs button').forEach(item => item.classList.toggle('active', item === button));
    $$('.tab-panel').forEach(panel => panel.classList.toggle('active', panel.dataset.panel === button.dataset.tab));
  }));

  $('#calendar-prev').addEventListener('click', () => {
    calendarCursor = new Date(calendarCursor.getFullYear(), calendarCursor.getMonth() - 1, 1);
    renderCalendar();
  });
  $('#calendar-next').addEventListener('click', () => {
    calendarCursor = new Date(calendarCursor.getFullYear(), calendarCursor.getMonth() + 1, 1);
    renderCalendar();
  });

  const settingMap = {
    '#participant-name': ['participantName', String],
    '#focus-minutes': ['focusMinutes', Number],
    '#break-minutes': ['breakMinutes', Number],
    '#long-break-minutes': ['longBreakMinutes', Number],
    '#long-break-cycle': ['cyclesBeforeLongBreak', Number],
    '#daily-goal-minutes': ['dailyGoalMinutes', Number],
    '#idle-threshold': ['idleThresholdSeconds', Number],
    '#window-lock': ['windowLockEnabled', element => element.checked],
    '#monitor-lock': ['monitorLockEnabled', element => element.checked],
    '#tab-lock': ['tabLockEnabled', element => element.checked],
    '#screen-inactive': ['pauseWhenScreenInactive', element => element.checked],
    '#record-urls': ['recordUrls', element => element.checked],
    '#alarm-enabled': ['alarmEnabled', element => element.checked],
    '#auto-overlay': ['autoOpenOverlay', element => element.checked]
  };
  for (const [selector, [key, transform]] of Object.entries(settingMap)) {
    const element = $(selector);
    element.addEventListener('change', () => window.nfc.updateSettings({ [key]: transform === String || transform === Number ? transform(element.value) : transform(element) }));
  }

  const themeMap = {
    '#timer-color': ['timerColor', String],
    '#accent-color': ['accentColor', String],
    '#panel-color': ['panelColor', String],
    '#panel-opacity': ['panelOpacity', Number],
    '#overlay-opacity': ['overlayOpacity', Number],
    '#theme-blur': ['blur', Number],
    '#timer-size': ['timerSize', Number],
    '#shadow-strength': ['shadowStrength', Number]
  };
  for (const [selector, [key, transform]] of Object.entries(themeMap)) {
    const element = $(selector);
    element.addEventListener('input', () => {
      const value = transform(element.value);
      state.settings.theme[key] = value;
      applyTheme(state.settings.theme);
      if (element.type === 'range') renderDashboard();
    });
    element.addEventListener('change', () => window.nfc.updateSettings({ theme: { [key]: transform(element.value) } }));
  }

  const presets = {
    lime: { timerColor: '#D7FF5F', accentColor: '#A7FF3F' },
    white: { timerColor: '#FFFFFF', accentColor: '#D7DEEA' },
    cyan: { timerColor: '#7EF9FF', accentColor: '#36DDEA' },
    amber: { timerColor: '#FFD166', accentColor: '#FFB52E' },
    pink: { timerColor: '#FF92D0', accentColor: '#FF58B0' }
  };
  $$('.preset-row button').forEach(button => button.addEventListener('click', () => window.nfc.updateSettings({ theme: presets[button.dataset.preset] })));

  $('#save-sync').addEventListener('click', async () => {
    await window.nfc.configureSync({
      endpoint: $('#sync-endpoint').value.trim(),
      accountId: $('#sync-account').value.trim(),
      token: $('#sync-token').value,
      enabled: true
    });
    $('#sync-token').value = '';
    $('#sync-status').textContent = '연동 설정을 안전 저장소에 저장했습니다.';
  });
  $('#sync-push').addEventListener('click', () => runSync('push'));
  $('#sync-pull').addEventListener('click', () => runSync('pull'));
  $('#export-data').addEventListener('click', window.nfc.exportData);
  $('#import-data').addEventListener('click', window.nfc.importData);
  $('#clear-history').addEventListener('click', async () => {
    if (confirm('모든 로컬 기록을 삭제할까요?')) await window.nfc.clearHistory();
  });
}

async function runSync(direction) {
  const status = $('#sync-status');
  status.textContent = '동기화 중…';
  try {
    await window.nfc.runSync(direction);
    status.textContent = direction === 'push' ? '서버 업로드 완료' : '서버 기록 병합 완료';
  } catch (error) {
    status.textContent = error.message;
  }
}

function bindOverlay() {
  $('#overlay-pause').addEventListener('click', window.nfc.togglePause);
  $('#overlay-stop').addEventListener('click', window.nfc.stopSession);
  $('#overlay-settings').addEventListener('click', window.nfc.showDashboard);
  $('#overlay-close').addEventListener('click', window.nfc.hideOverlay);
  window.nfc.onOverlayUnlock(unlocked => document.body.classList.toggle('overlay-unlocked', unlocked));
}

async function init() {
  state = await window.nfc.getState();
  if (isOverlay) {
    $('#overlay-view').hidden = false;
    bindOverlay();
    renderOverlay();
  } else {
    $('#dashboard').hidden = false;
    bindDashboard();
    await refreshContext();
    renderDashboard();
  }
  window.nfc.onState(next => {
    state = next;
    isOverlay ? renderOverlay() : renderDashboard();
  });
}

void init();
