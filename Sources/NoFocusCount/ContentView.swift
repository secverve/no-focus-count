import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var timerHovered = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 18) {
                    header
                    timerStage
                    sessionShortcut
                    focusInspector

                    if !model.accessibilityTrusted {
                        permissionBanner
                    }

                    metrics
                    leaderboard
                    commentary
                }
                .padding(26)
            }
        }
        .frame(minWidth: 760, minHeight: 670)
        .preferredColorScheme(.dark)
        .onAppear { model.refreshWindows() }
        .sheet(isPresented: $showSettings) {
            SessionSettingsView(model: model)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(model: model, showDeleteConfirmation: $showDeleteConfirmation)
        }
        .confirmationDialog("모든 집중 기록을 삭제할까요?", isPresented: $showDeleteConfirmation) {
            Button("모두 삭제", role: .destructive) { model.deleteHistory() }
        }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.025, green: 0.028, blue: 0.032)
            RadialGradient(
                colors: [statusColor.opacity(0.10), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.nfcLime)
                .frame(width: 9, height: 9)
                .shadow(color: .nfcLime.opacity(0.8), radius: 8)

            Text("NO FOCUS COUNT")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(1.7)

            Text("LOCAL ONLY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.nfcLime)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.nfcLime.opacity(0.08), in: Capsule())

            Spacer()

            NFCIconButton(icon: "rectangle.on.rectangle.angled", help: "집중 창 선택기") {
                model.showWindowSwitcher()
            }
            NFCIconButton(icon: "rectangle.on.rectangle", help: "미니 타이머 열기") {
                model.showMiniTimer()
            }
            NFCIconButton(icon: "clock.arrow.circlepath", help: "지난 기록") {
                showHistory = true
            }
            NFCIconButton(icon: "slider.horizontal.3", help: "세션 설정") {
                showSettings = true
            }
        }
    }

    private var timerStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(timerHovered ? 0.045 : 0.025))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(statusColor.opacity(timerHovered ? 0.42 : 0.16), lineWidth: 1)
                }

            VStack(spacing: 9) {
                Text(phaseEmoji)
                    .font(.system(size: 23))
                    .opacity(timerHovered ? 1 : 0.65)

                Text(model.remainingFocusSeconds.clockText)
                    .font(.system(size: 88, weight: .medium, design: .monospaced).monospacedDigit())
                    .tracking(-5)
                    .contentTransition(.numericText())

                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: statusColor.opacity(0.7), radius: 5)
                    Text(model.phase.label.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }

                timerControls
                    .padding(.top, 13)
                    .opacity(timerHovered ? 1 : 0)
                    .offset(y: timerHovered ? 0 : 5)
                    .allowsHitTesting(timerHovered)
            }

            if !timerHovered {
                Text("HOVER TO CONTROL")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.tertiary)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 18)
            }
        }
        .frame(height: 300)
        .animation(.easeOut(duration: 0.18), value: timerHovered)
        .onHover { timerHovered = $0 }
    }

    private var timerControls: some View {
        HStack(spacing: 10) {
            if model.currentSession == nil {
                Button {
                    if model.canStart {
                        model.startSession()
                    } else {
                        showSettings = true
                    }
                } label: {
                    Label(model.canStart ? "START" : "SET TARGET", systemImage: model.canStart ? "play.fill" : "scope")
                }
                .buttonStyle(NFCPillButtonStyle(primary: true))
            } else {
                Button {
                    model.toggleManualPause()
                } label: {
                    Label(model.phase == .pausedByUser ? "RESUME" : "PAUSE", systemImage: model.phase == .pausedByUser ? "play.fill" : "pause.fill")
                }
                .buttonStyle(NFCPillButtonStyle(primary: true))

                Button {
                    model.stopSession()
                } label: {
                    Label("FINISH", systemImage: "stop.fill")
                }
                .buttonStyle(NFCPillButtonStyle())
            }

            Button {
                model.showMiniTimer()
            } label: {
                Image(systemName: "pin.fill")
            }
            .buttonStyle(NFCPillButtonStyle())
            .help("시간만 띄우기")
        }
    }

    private var sessionShortcut: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(Color.nfcLime)
                Text(cleanParticipantName)
                    .font(.callout.weight(.semibold))
                Text("/").foregroundStyle(.tertiary)
                Image(systemName: "macwindow")
                    .foregroundStyle(.secondary)
                Text(model.selectedWindow?.identityLabel ?? "집중할 창을 선택하세요")
                    .lineLimit(1)
                    .foregroundStyle(model.selectedWindow == nil ? Color.orange : Color.secondary)
                Spacer()
                Text("\(model.focusMinutes) MIN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                if model.captureFocusReceipts {
                    Text("RECEIPTS ON")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.nfcLime)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var focusInspector: some View {
        let target = model.currentSession?.target ?? model.selectedWindow
        let snapshot = model.latestSnapshot
        let status = model.latestFocusStatus

        return HStack(spacing: 10) {
            contextCell(
                eyebrow: "SELECTED WINDOW",
                title: target.map { "\($0.appName) · #\($0.id)" } ?? "선택 없음",
                detail: target.map { "\($0.title.isEmpty ? "제목 없음" : $0.title) · \($0.monitorName ?? "모니터 미확인")" } ?? "설정에서 창을 골라주세요",
                tint: .nfcLime
            )
            contextCell(
                eyebrow: "ACTIVE NOW",
                title: snapshot.map { "\($0.frontmostAppName) · #\($0.frontmostWindowID.map(String.init) ?? "?")" } ?? "측정 대기",
                detail: snapshot.map { "\($0.frontmostWindowTitle.isEmpty ? "제목 없음" : $0.frontmostWindowTitle) · \($0.frontmostMonitorName ?? "모니터 미확인")" } ?? "1초마다 갱신됩니다",
                tint: .cyan
            )
            contextCell(
                eyebrow: "TIMER VERDICT",
                title: status?.label ?? "판정 대기",
                detail: snapshot.map { "창 노출 \(Int(($0.targetVisibleFraction * 100).rounded()))% · \($0.capturedAt.formatted(date: .omitted, time: .standard))" } ?? "선택 창과 현재 창을 비교합니다",
                tint: status == .focused ? .nfcLime : .orange
            )
        }
    }

    private func contextCell(eyebrow: String, title: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(eyebrow)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.7)
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            Text("창 판정을 위해 손쉬운 사용 권한이 필요합니다. 키 입력은 읽지 않아요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("OPEN SETTINGS") { model.requestAccessibilityPermission() }
                .buttonStyle(NFCPillButtonStyle())
        }
        .padding(14)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.16))
        }
    }

    private var metrics: some View {
        let session = model.currentSession ?? model.lastSessionSummary ?? model.history.first
        return HStack(spacing: 12) {
            NFCMetric(title: "FOCUS", value: session?.completedFocusSeconds.clockText ?? "00:00", icon: "timer")
            NFCMetric(title: "ESCAPES", value: "\(session?.distractionCount ?? 0)", icon: "arrow.up.right")
            NFCMetric(title: "LOST", value: session?.totalDistractionSeconds.clockText ?? "00:00", icon: "hourglass.bottomhalf.filled")
            NFCMetric(title: "COMBO", value: "×\(model.focusCombo)", icon: "flame.fill")
        }
    }

    @ViewBuilder
    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LOCAL LEADERBOARD")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.3)
                Spacer()
                Text("이 Mac의 세션만 집계")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let best = model.localLeaderboard.first,
               let worst = model.localLeaderboard.last {
                HStack(spacing: 12) {
                    LeaderCard(
                        eyebrow: "🏆 제일 잘한 사람",
                        stats: best,
                        tint: .nfcLime
                    )
                    LeaderCard(
                        eyebrow: "🫠 제일 못한 사람",
                        stats: worst,
                        tint: .orange
                    )
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(Color.nfcLime)
                    Text("첫 세션을 끝내면 로컬 랭킹이 열립니다.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(18)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var commentary: some View {
        HStack(alignment: .top, spacing: 13) {
            Text("NFC")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.nfcLime, in: Capsule())

            Text(model.latestCommentary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(17)
        .background(Color.nfcLime.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(Color.nfcLime.opacity(0.12))
        }
    }

    private var cleanParticipantName: String {
        let value = model.participantName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "나" : value
    }

    private var phaseEmoji: String {
        switch model.phase {
        case .idle: "◉"
        case .arming: "🎯"
        case .focusing: "🫡"
        case .pausedByUser: "☕️"
        case .pausedByDistraction: "👀"
        case .completed: "🏆"
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .focusing: .nfcLime
        case .pausedByDistraction: .orange
        case .pausedByUser: .yellow
        case .completed: .cyan
        case .idle, .arming: .white.opacity(0.55)
        }
    }
}

private struct SessionSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 0.035, green: 0.038, blue: 0.043).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SESSION SETUP")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                        Text("누가, 어떤 창에서, 얼마나 집중할지")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("DONE") { dismiss() }
                        .buttonStyle(NFCPillButtonStyle(primary: true))
                }
                .padding(.leading, 24)
                .padding(.trailing, 68)
                .padding(.vertical, 18)
                .background(Color(red: 0.035, green: 0.038, blue: 0.043).opacity(0.96))

                ScrollView {
                    VStack(spacing: 14) {
                        NFCSettingRow(title: "이름", subtitle: "이 Mac의 로컬 랭킹에 표시됩니다") {
                            TextField("나", text: $model.participantName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 240)
                        }

                        WindowPickerView(model: model)

                        NFCSettingRow(title: "집중 시간", subtitle: "5분부터 120분까지") {
                            Stepper("\(model.focusMinutes)분", value: $model.focusMinutes, in: 5...120, step: 5)
                                .frame(maxWidth: 160)
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("최소 창 노출")
                                        .font(.callout.weight(.semibold))
                                    Text("\(Int(model.minimumVisiblePercent))% 이상 보여야 집중으로 인정")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            Slider(value: $model.minimumVisiblePercent, in: 30...100, step: 5)
                                .tint(.nfcLime)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

                        NFCSettingRow(title: "브라우저 URL 기록", subtitle: "선택 동의 · 페이지 내용과 입력값은 수집하지 않음") {
                            Toggle("", isOn: $model.recordBrowserURLs)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(.nfcLime)
                        }

                        NFCSettingRow(title: "Focus Receipt", subtitle: "2초 이상 이탈할 때 해당 창의 저해상도 사진 1장만 로컬 저장") {
                            Toggle("", isOn: $model.captureFocusReceipts)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(.nfcLime)
                                .onChange(of: model.captureFocusReceipts) { _, enabled in
                                    if enabled && !model.screenCaptureTrusted {
                                        model.requestScreenCapturePermission()
                                    }
                                }
                        }

                        NFCSettingRow(title: "완료 알람", subtitle: "소리, macOS 알림, Dock 표시로 타이머 완료 안내") {
                            Toggle("", isOn: $model.alarmEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(.nfcLime)
                                .onChange(of: model.alarmEnabled) { _, enabled in
                                    if enabled { model.requestAlarmPermission() }
                                }
                        }

                        if model.captureFocusReceipts && !model.screenCaptureTrusted {
                            HStack {
                                Text("화면 기록 권한을 허용한 뒤 앱을 다시 실행하면 Focus Receipt가 활성화됩니다.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button("화면 기록 설정") { model.requestScreenCapturePermission() }
                                    .buttonStyle(NFCPillButtonStyle())
                            }
                        }

                        if !model.accessibilityTrusted {
                            Button("손쉬운 사용 설정 열기") { model.requestAccessibilityPermission() }
                                .buttonStyle(NFCPillButtonStyle())
                        }

                        Text("모든 기록은 이 Mac에만 저장됩니다. 키 입력, 화면 이미지, SNS 본문은 읽지 않습니다.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("설정 닫기 (Esc)")
            .accessibilityLabel("설정 닫기")
            .padding(14)
            .zIndex(10)
        }
        .frame(minWidth: 420, idealWidth: 680, maxWidth: 780, minHeight: 360, idealHeight: 680, maxHeight: 780)
        .preferredColorScheme(.dark)
        .onAppear { model.refreshWindows() }
    }
}

private struct WindowPickerView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 9)]

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.nfcLime.opacity(0.09))
                Image(systemName: "display.2")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.nfcLime)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("모니터와 집중 창")
                    .font(.callout.weight(.semibold))
                Text(model.selectedDisplay?.displayName ?? "모니터 선택 필요")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.nfcLime)
                Text(model.selectedWindow?.identityLabel ?? "선택한 모니터의 창을 큰 미리보기로 고르세요")
                    .font(.caption)
                    .foregroundStyle(model.selectedWindow == nil ? Color.orange : Color.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button {
                model.showWindowSwitcher()
            } label: {
                Label("ALT-TAB 창 선택", systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(NFCPillButtonStyle(primary: true))
            .disabled(model.currentSession != nil)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        }
    }

    private var legacyPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("집중할 창")
                        .font(.callout.weight(.semibold))
                    Text(selectedSummary)
                        .font(.caption)
                        .foregroundStyle(model.selectedWindow == nil ? Color.orange : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    model.beginQuickWindowPick()
                } label: {
                    Label(
                        model.windowPickCountdown.map { "\($0)초 뒤 선택" } ?? "3초 자동 선택",
                        systemImage: "scope"
                    )
                }
                .buttonStyle(NFCPillButtonStyle(primary: true))
                .disabled(model.windowPickCountdown != nil || model.currentSession != nil)

                Button {
                    model.refreshWindows()
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .buttonStyle(NFCPillButtonStyle())
            }

            if let message = model.windowPickMessage {
                Label(message, systemImage: model.windowPickError ? "exclamationmark.circle" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(model.windowPickError ? Color.orange : Color.nfcLime)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("앱 이름이나 창 제목 검색", text: $searchText)
                    .textFieldStyle(.plain)
                Text("\(filteredWindows.count)개")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
            }

            if filteredWindows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !visibleWindows.isEmpty {
                            windowSection(title: "지금 화면에 보이는 창", windows: visibleWindows, tint: .nfcLime)
                        }
                        if !otherWindows.isEmpty {
                            windowSection(title: "다른 Space · 최소화된 창", windows: otherWindows, tint: .orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 120, maxHeight: 310)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        }
    }

    private var filteredWindows: [TrackedWindow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.windows }
        return model.windows.filter { window in
            [window.appName, window.title, window.monitorName ?? "", String(window.id)]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var visibleWindows: [TrackedWindow] {
        filteredWindows.filter { $0.isOnScreen != false }
    }

    private var otherWindows: [TrackedWindow] {
        filteredWindows.filter { $0.isOnScreen == false }
    }

    private var selectedSummary: String {
        guard let selected = model.selectedWindow else {
            return "아래 카드에서 고르거나 자동 선택을 사용하세요"
        }
        return "선택됨 · \(selected.appName) · \(pickerTitle(selected))"
    }

    @ViewBuilder
    private func windowSection(title: String, windows: [TrackedWindow], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text("\(windows.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
                ForEach(windows) { window in
                    windowCard(window)
                }
            }
        }
    }

    private func windowCard(_ window: TrackedWindow) -> some View {
        let selected = model.selectedWindowID == window.id
        return Button {
            model.selectWindow(window)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                appIcon(for: window)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(window.appName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.nfcLime)
                        }
                    }
                    Text(pickerTitle(window))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 5) {
                        Image(systemName: "display")
                        Text(window.monitorName ?? "모니터 미확인")
                        Text("· #\(window.id)")
                    }
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                selected ? Color.nfcLime.opacity(0.10) : Color.white.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(selected ? Color.nfcLime.opacity(0.65) : Color.white.opacity(0.07), lineWidth: selected ? 1.2 : 0.7)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.currentSession != nil)
    }

    @ViewBuilder
    private func appIcon(for window: TrackedWindow) -> some View {
        if let icon = NSRunningApplication(processIdentifier: window.ownerPID)?.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
        } else {
            Image(systemName: "macwindow")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private func pickerTitle(_ window: TrackedWindow) -> String {
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty else { return title }
        let siblings = model.windows.filter { $0.ownerPID == window.ownerPID }
        let ordinal = (siblings.firstIndex(where: { $0.id == window.id }) ?? 0) + 1
        return "제목 없는 창 \(ordinal)"
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "macwindow.badge.xmark")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
            Text(searchText.isEmpty ? "선택할 수 있는 창을 찾지 못했습니다" : "검색 결과가 없습니다")
                .font(.callout.weight(.semibold))
            Text(searchText.isEmpty ? "손쉬운 사용 권한을 확인한 뒤 새로고침하거나 3초 자동 선택을 사용하세요." : "다른 앱 이름이나 창 제목으로 검색해 보세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if searchText.isEmpty && !model.accessibilityTrusted {
                Button("손쉬운 사용 설정 열기") { model.requestAccessibilityPermission() }
                    .buttonStyle(NFCPillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }
}

private struct HistoryView: View {
    @ObservedObject var model: AppModel
    @Binding var showDeleteConfirmation: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.038, blue: 0.043).ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Text("SESSION HISTORY")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                    Spacer()
                    if !model.history.isEmpty {
                        Button("DELETE ALL", role: .destructive) { showDeleteConfirmation = true }
                            .buttonStyle(NFCPillButtonStyle())
                    }
                    Button("DONE") { dismiss() }
                        .buttonStyle(NFCPillButtonStyle(primary: true))
                }

                if model.history.isEmpty {
                    Spacer()
                    Text("아직 기록이 없습니다.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(model.history) { session in
                                DisclosureGroup {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .top, spacing: 9) {
                                            Image(systemName: session.distractions.isEmpty ? "checkmark.seal.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                                                .foregroundStyle(session.distractions.isEmpty ? Color.nfcLime : Color.orange)
                                            Text(session.activityNarrative)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(12)
                                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))

                                        if session.distractions.isEmpty {
                                            Text("이탈 기록 없음").foregroundStyle(.secondary)
                                        }
                                        ForEach(session.distractions) { event in
                                            HStack(alignment: .top, spacing: 10) {
                                                VStack(alignment: .trailing, spacing: 3) {
                                                    Text(event.startedAt.formatted(date: .omitted, time: .shortened))
                                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                                    Image(systemName: "arrow.down")
                                                        .font(.system(size: 9))
                                                }
                                                .foregroundStyle(.tertiary)
                                                .frame(width: 58, alignment: .trailing)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(event.destinationLabel).font(.callout.weight(.semibold)).lineLimit(2)
                                                    Text("\(event.status.label) · \(event.duration.koreanDurationText) 머묾")
                                                        .font(.caption2)
                                                        .foregroundStyle(.orange)
                                                    if !event.windowTitle.isEmpty {
                                                        Text("이 창으로 이동한 기록")
                                                            .font(.caption2)
                                                            .foregroundStyle(.tertiary)
                                                    }
                                                    if let url = event.url {
                                                        Text(url).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(2)
                                                    }
                                                    if let path = event.visualReceiptPath,
                                                       let image = NSImage(contentsOfFile: path) {
                                                        Image(nsImage: image)
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(maxWidth: 360, minHeight: 100, maxHeight: 170)
                                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                                            .overlay(alignment: .bottomLeading) {
                                                                Text("FOCUS RECEIPT")
                                                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                                    .padding(6)
                                                                    .background(.black.opacity(0.72), in: Capsule())
                                                                    .padding(7)
                                                            }
                                                            .padding(.top, 5)
                                                    }
                                                }
                                                Spacer()
                                                Text(event.duration.koreanDurationText)
                                                    .font(.caption.monospacedDigit())
                                            }
                                            .padding(.vertical, 5)
                                        }
                                    }
                                    .padding(.top, 10)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(session.participantDisplayName)
                                                .font(.headline)
                                            Text(session.startedAt.shortDateTimeText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("\(session.target.appName) · \(session.targetMonitorName ?? session.target.monitorName ?? "모니터 미확인")")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        Text("\(Int(session.focusScore))%")
                                            .font(.title3.monospacedDigit().weight(.bold))
                                            .foregroundStyle(session.focusScore >= 70 ? Color.nfcLime : Color.orange)
                                        Text("· \(session.distractionCount)회")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(16)
                                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 760, height: 640)
        .preferredColorScheme(.dark)
    }
}

private struct NFCMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Color.nfcLime.opacity(0.8))
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15).stroke(Color.white.opacity(0.055))
        }
    }
}

private struct LeaderCard: View {
    let eyebrow: String
    let stats: ParticipantStats
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(tint.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: stats.focusScore / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(stats.focusScore))")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(stats.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(stats.sessionCount)세션 · 이탈 \(stats.totalDistractionCount)회")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.13))
        }
    }
}

private struct NFCSettingRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            content
        }
        .padding(16)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct NFCIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(hovered ? 0.09 : 0.035), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovered ? Color.white : Color.secondary)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct NFCPillButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(primary ? Color.black : Color.white.opacity(0.82))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                primary
                    ? Color.nfcLime.opacity(configuration.isPressed ? 0.72 : 1)
                    : Color.white.opacity(configuration.isPressed ? 0.13 : 0.07),
                in: Capsule()
            )
            .overlay {
                if !primary {
                    Capsule().stroke(Color.white.opacity(0.09))
                }
            }
    }
}

extension Color {
    static let nfcLime = Color(red: 0.67, green: 1.0, blue: 0.36)
}
