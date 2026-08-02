import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showHistory = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                if !model.accessibilityTrusted {
                    permissionBanner
                }

                timerCard

                if model.currentSession == nil {
                    setupCard
                } else {
                    liveSessionCard
                }

                if let summary = model.lastSessionSummary {
                    summaryCard(summary)
                }

                historyCard
                privacyCard
            }
            .padding(24)
        }
        .frame(minWidth: 720, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("모든 집중 기록을 삭제할까요?", isPresented: $showDeleteConfirmation) {
            Button("모두 삭제", role: .destructive) { model.deleteHistory() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("No Focus Count")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("집중에서 벗어난 횟수와 시간을 솔직하게 기록합니다.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            Text(model.phase.label)
                .font(.callout.weight(.semibold))
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("손쉬운 사용 권한이 필요합니다")
                    .font(.headline)
                Text("활성 창 제목을 판별할 때만 사용하며 키 입력은 읽지 않습니다. 권한을 켠 뒤 앱을 다시 실행하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("설정 열기") { model.requestAccessibilityPermission() }
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private var timerCard: some View {
        VStack(spacing: 10) {
            Text(model.remainingFocusSeconds.clockText)
                .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
            Text(model.phase.label)
                .font(.headline)
                .foregroundStyle(statusColor)

            HStack(spacing: 10) {
                if model.currentSession == nil {
                    Button {
                        model.startSession()
                    } label: {
                        Label("집중 시작", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canStart)
                } else {
                    Button {
                        model.toggleManualPause()
                    } label: {
                        Label(model.phase == .pausedByUser ? "계속" : "일시정지", systemImage: model.phase == .pausedByUser ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        model.stopSession()
                    } label: {
                        Label("종료 및 집계", systemImage: "stop.fill")
                    }
                    .controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var setupCard: some View {
        GroupBox("집중 세션 설정") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("집중할 창", selection: $model.selectedWindowID) {
                        Text("창을 선택하세요").tag(Optional<UInt32>.none)
                        ForEach(model.windows) { window in
                            Text(window.displayName).tag(Optional(window.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button {
                        model.refreshWindows()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("창 목록 새로고침")
                }

                Stepper("집중 시간: \(model.focusMinutes)분", value: $model.focusMinutes, in: 5...120, step: 5)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("창이 최소 \(Int(model.minimumVisiblePercent))% 보여야 집중으로 인정")
                        Spacer()
                    }
                    Slider(value: $model.minimumVisiblePercent, in: 30...100, step: 5)
                }

                Toggle("브라우저 이탈 시 현재 URL 기록", isOn: $model.recordBrowserURLs)
                Text("선택 동의 항목입니다. Safari·Chrome·Brave·Edge의 현재 탭 주소만 기록하며 페이지 내용, 입력값, 화면은 읽지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private var liveSessionCard: some View {
        GroupBox("현재 세션") {
            VStack(alignment: .leading, spacing: 10) {
                if let session = model.currentSession {
                    Label(session.target.displayName, systemImage: "macwindow")
                    Divider()
                    metricRow("집중한 시간", session.completedFocusSeconds.clockText)
                    metricRow("이탈 횟수", "\(session.distractionCount)회")
                    metricRow("이탈 시간", session.totalDistractionSeconds.clockText)

                    if let latest = session.distractions.last {
                        Divider()
                        Text("최근 이탈")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text([latest.appName, latest.windowTitle].filter { !$0.isEmpty }.joined(separator: " · "))
                            .lineLimit(2)
                        if let url = latest.url {
                            Text(url)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }

    private func summaryCard(_ session: FocusSession) -> some View {
        GroupBox("방금 끝난 세션") {
            HStack(spacing: 24) {
                summaryMetric("집중", session.completedFocusSeconds.clockText, "timer")
                summaryMetric("이탈", "\(session.distractionCount)회", "arrow.turn.up.right")
                summaryMetric("이탈 시간", session.totalDistractionSeconds.clockText, "clock.badge.exclamationmark")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private var historyCard: some View {
        GroupBox {
            DisclosureGroup("지난 세션 \(model.history.count)개", isExpanded: $showHistory) {
                if model.history.isEmpty {
                    Text("아직 저장된 세션이 없습니다.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.history.prefix(20)) { session in
                            sessionHistoryRow(session)
                            Divider()
                        }
                        HStack {
                            Spacer()
                            Button("기록 모두 삭제", role: .destructive) { showDeleteConfirmation = true }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    private func sessionHistoryRow(_ session: FocusSession) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if session.distractions.isEmpty {
                    Text("이탈 기록 없음").foregroundStyle(.secondary)
                }
                ForEach(session.distractions) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(event.appName).font(.callout.weight(.semibold))
                            Spacer()
                            Text(event.duration.clockText).font(.caption.monospacedDigit())
                        }
                        if !event.windowTitle.isEmpty {
                            Text(event.windowTitle).font(.caption).lineLimit(1)
                        }
                        if let url = event.url {
                            Text(url).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(session.startedAt.shortDateTimeText)
                    Text(session.target.appName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("집중 \(session.completedFocusSeconds.clockText) · 이탈 \(session.distractionCount)회")
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.green)
            Text("기록은 이 Mac의 Application Support 폴더에만 JSON으로 저장됩니다. 서버 전송, 계정 추적, 키 입력 수집, 화면 캡처는 하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit().weight(.semibold))
        }
    }

    private func summaryMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
            Text(value).font(.title3.monospacedDigit().weight(.bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusColor: Color {
        switch model.phase {
        case .focusing: .green
        case .pausedByDistraction: .orange
        case .pausedByUser: .yellow
        case .completed: .blue
        case .idle, .arming: .secondary
        }
    }
}
