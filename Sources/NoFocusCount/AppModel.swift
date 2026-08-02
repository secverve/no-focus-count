import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var windows: [TrackedWindow] = []
    @Published var selectedWindowID: UInt32?
    @Published private(set) var phase: TimerPhase = .idle
    @Published private(set) var remainingFocusSeconds: TimeInterval = 25 * 60
    @Published private(set) var currentSession: FocusSession?
    @Published private(set) var lastSessionSummary: FocusSession?
    @Published private(set) var history: [FocusSession]
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var screenCaptureTrusted = false

    @Published var participantName: String {
        didSet { UserDefaults.standard.set(participantName, forKey: Keys.participantName) }
    }

    @Published var focusMinutes: Int {
        didSet {
            UserDefaults.standard.set(focusMinutes, forKey: Keys.focusMinutes)
            if currentSession == nil { remainingFocusSeconds = TimeInterval(focusMinutes * 60) }
        }
    }

    @Published var minimumVisiblePercent: Double {
        didSet { UserDefaults.standard.set(minimumVisiblePercent, forKey: Keys.minimumVisiblePercent) }
    }

    @Published var recordBrowserURLs: Bool {
        didSet { UserDefaults.standard.set(recordBrowserURLs, forKey: Keys.recordBrowserURLs) }
    }

    @Published var captureFocusReceipts: Bool {
        didSet { UserDefaults.standard.set(captureFocusReceipts, forKey: Keys.captureFocusReceipts) }
    }

    @Published var alarmEnabled: Bool {
        didSet { UserDefaults.standard.set(alarmEnabled, forKey: Keys.alarmEnabled) }
    }

    private enum Keys {
        static let focusMinutes = "focusMinutes"
        static let minimumVisiblePercent = "minimumVisiblePercent"
        static let recordBrowserURLs = "recordBrowserURLs"
        static let participantName = "participantName"
        static let captureFocusReceipts = "captureFocusReceipts"
        static let alarmEnabled = "alarmEnabled"
    }

    private let monitor: ActivityMonitor
    private let repository: SessionRepository
    private let receiptCapture: FocusReceiptCapture
    private let focusAlarm: FocusAlarm
    private var timer: Timer?
    private var lastTick = Date()
    private var graceUntil: Date?
    private var currentDistractionIndex: Int?
    private var miniTimerPanel: MiniTimerPanelController?

    init(
        monitor: ActivityMonitor = ActivityMonitor(),
        repository: SessionRepository? = nil,
        receiptCapture: FocusReceiptCapture = FocusReceiptCapture(),
        focusAlarm: FocusAlarm = FocusAlarm()
    ) {
        self.monitor = monitor
        self.repository = repository ?? SessionRepository()
        self.receiptCapture = receiptCapture
        self.focusAlarm = focusAlarm

        let storedMinutes = UserDefaults.standard.integer(forKey: Keys.focusMinutes)
        focusMinutes = storedMinutes == 0 ? 25 : storedMinutes
        let storedVisibility = UserDefaults.standard.double(forKey: Keys.minimumVisiblePercent)
        minimumVisiblePercent = storedVisibility == 0 ? 65 : storedVisibility
        recordBrowserURLs = UserDefaults.standard.bool(forKey: Keys.recordBrowserURLs)
        participantName = UserDefaults.standard.string(forKey: Keys.participantName) ?? "나"
        captureFocusReceipts = UserDefaults.standard.bool(forKey: Keys.captureFocusReceipts)
        alarmEnabled = UserDefaults.standard.object(forKey: Keys.alarmEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.alarmEnabled)
        remainingFocusSeconds = TimeInterval((storedMinutes == 0 ? 25 : storedMinutes) * 60)
        history = self.repository.sessions
        accessibilityTrusted = monitor.isAccessibilityTrusted
        screenCaptureTrusted = receiptCapture.hasPermission

        refreshWindows()
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    var selectedWindow: TrackedWindow? {
        guard let selectedWindowID else { return nil }
        return windows.first { $0.id == selectedWindowID }
    }

    var canStart: Bool {
        selectedWindow != nil && currentSession == nil
    }

    var localLeaderboard: [ParticipantStats] {
        LeaderboardCalculator.rankings(from: history)
    }

    var focusCombo: Int {
        var count = 0
        for session in history {
            guard session.focusScore >= 80 else { break }
            count += 1
        }
        return count
    }

    var latestCommentary: String {
        guard let session = lastSessionSummary ?? history.first else {
            return "첫 세션을 끝내면 No Focus Count가 솔직한 한마디를 남겨드려요."
        }
        return FocusCommentary.message(for: session.focusScore, distractionCount: session.distractionCount)
    }

    func refreshWindows() {
        windows = monitor.availableWindows()
        if selectedWindow == nil {
            selectedWindowID = windows.first?.id
        }
        accessibilityTrusted = monitor.isAccessibilityTrusted
    }

    func requestAccessibilityPermission() {
        monitor.requestAccessibilityPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestScreenCapturePermission() {
        screenCaptureTrusted = receiptCapture.requestPermission()
        if !screenCaptureTrusted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func showMiniTimer() {
        if miniTimerPanel == nil {
            miniTimerPanel = MiniTimerPanelController(model: self)
        }
        miniTimerPanel?.show()
    }

    func requestAlarmPermission() {
        focusAlarm.requestNotificationPermission()
    }

    func startSession() {
        guard let target = selectedWindow else { return }
        let plannedSeconds = TimeInterval(focusMinutes * 60)
        currentSession = FocusSession(
            id: UUID(),
            startedAt: Date(),
            endedAt: nil,
            participantName: participantName,
            plannedFocusSeconds: plannedSeconds,
            completedFocusSeconds: 0,
            target: target,
            distractions: []
        )
        remainingFocusSeconds = plannedSeconds
        currentDistractionIndex = nil
        lastSessionSummary = nil
        graceUntil = Date().addingTimeInterval(2)
        lastTick = Date()
        phase = .arming

        if let application = NSRunningApplication(processIdentifier: target.ownerPID) {
            if #available(macOS 14.0, *) {
                application.activate()
            } else {
                application.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    func toggleManualPause() {
        guard currentSession != nil else { return }
        switch phase {
        case .pausedByUser:
            phase = .focusing
            lastTick = Date()
        case .arming, .focusing, .pausedByDistraction:
            closeCurrentDistraction(at: Date())
            phase = .pausedByUser
        case .idle, .completed:
            break
        }
    }

    func stopSession() {
        finishSession(completed: false)
    }

    func deleteHistory() {
        repository.deleteAll()
        receiptCapture.deleteAll()
        history = []
        lastSessionSummary = nil
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer?.tolerance = 0.15
    }

    private func tick() {
        let now = Date()
        accessibilityTrusted = monitor.isAccessibilityTrusted
        screenCaptureTrusted = receiptCapture.hasPermission

        guard var session = currentSession else {
            lastTick = now
            return
        }

        guard phase != .pausedByUser else {
            lastTick = now
            return
        }

        if let graceUntil, now < graceUntil {
            lastTick = now
            return
        }
        graceUntil = nil

        let elapsed = min(2, max(0, now.timeIntervalSince(lastTick)))
        lastTick = now
        let snapshot = monitor.snapshot(for: session.target)
        let status = FocusPolicy.evaluate(
            snapshot: snapshot,
            target: session.target,
            minimumVisibleFraction: minimumVisiblePercent / 100
        )

        if status == .focused {
            closeCurrentDistraction(at: now)
            phase = .focusing
            session = currentSession ?? session
            session.completedFocusSeconds += elapsed
            currentSession = session
            remainingFocusSeconds = max(0, session.plannedFocusSeconds - session.completedFocusSeconds)
            if remainingFocusSeconds <= 0 {
                finishSession(completed: true)
            }
        } else {
            phase = .pausedByDistraction(status)
            recordDistraction(snapshot: snapshot, status: status)
        }
    }

    private func recordDistraction(snapshot: ActivitySnapshot, status: FocusStatus) {
        guard var session = currentSession else { return }

        if let index = currentDistractionIndex,
           session.distractions.indices.contains(index) {
            let current = session.distractions[index]
            let sameActivity = current.status == status
                && current.bundleIdentifier == snapshot.frontmostBundleIdentifier
                && current.windowTitle == snapshot.frontmostWindowTitle
            if sameActivity { return }
            session.distractions[index].endedAt = snapshot.capturedAt
        }

        var event = DistractionEvent(
            id: UUID(),
            startedAt: snapshot.capturedAt,
            endedAt: nil,
            status: status,
            appName: snapshot.frontmostAppName,
            bundleIdentifier: snapshot.frontmostBundleIdentifier,
            windowTitle: snapshot.frontmostWindowTitle,
            url: nil
        )

        if recordBrowserURLs {
            event.url = monitor.browserURL(bundleIdentifier: snapshot.frontmostBundleIdentifier)
        }

        session.distractions.append(event)
        currentDistractionIndex = session.distractions.indices.last
        currentSession = session

        if captureFocusReceipts,
           let windowID = snapshot.frontmostWindowID {
            scheduleFocusReceipt(eventID: event.id, windowID: windowID)
        }
    }

    private func scheduleFocusReceipt(eventID: UUID, windowID: UInt32) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self,
                  self.captureFocusReceipts,
                  let index = self.currentDistractionIndex,
                  let session = self.currentSession,
                  session.distractions.indices.contains(index),
                  session.distractions[index].id == eventID else { return }

            guard let path = await self.receiptCapture.capture(windowID: windowID, eventID: eventID),
                  var updatedSession = self.currentSession,
                  updatedSession.distractions.indices.contains(index),
                  updatedSession.distractions[index].id == eventID else { return }

            updatedSession.distractions[index].visualReceiptPath = path
            self.currentSession = updatedSession
            self.screenCaptureTrusted = self.receiptCapture.hasPermission
        }
    }

    private func closeCurrentDistraction(at date: Date) {
        guard var session = currentSession,
              let index = currentDistractionIndex,
              session.distractions.indices.contains(index) else {
            currentDistractionIndex = nil
            return
        }
        session.distractions[index].endedAt = date
        currentDistractionIndex = nil
        currentSession = session
    }

    private func finishSession(completed: Bool) {
        guard currentSession != nil else { return }
        closeCurrentDistraction(at: Date())
        guard var session = currentSession else { return }
        session.endedAt = Date()
        currentSession = nil
        currentDistractionIndex = nil
        repository.add(session)
        history = repository.sessions
        lastSessionSummary = session
        if completed && alarmEnabled {
            focusAlarm.fire(participantName: session.participantDisplayName)
        }
        phase = completed ? .completed : .idle
        remainingFocusSeconds = completed ? 0 : TimeInterval(focusMinutes * 60)
    }
}
