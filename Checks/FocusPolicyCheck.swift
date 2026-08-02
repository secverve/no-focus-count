import Foundation

@main
struct FocusPolicyCheck {
    static func main() {
        let target = TrackedWindow(
            id: 42,
            ownerPID: 100,
            appName: "Study App",
            bundleIdentifier: "test.study",
            title: "Chapter 1"
        )

        expect(
            snapshot(pid: 100, windowID: 42, onScreen: true, visible: 0.9),
            target: target,
            result: .focused
        )
        expect(
            snapshot(pid: 200, windowID: 50, onScreen: true, visible: 1),
            target: target,
            result: .differentApplication
        )
        expect(
            snapshot(pid: 100, windowID: 77, onScreen: true, visible: 1),
            target: target,
            result: .differentWindow
        )
        expect(
            snapshot(pid: 100, windowID: 42, onScreen: true, visible: 0.3),
            target: target,
            result: .targetCovered
        )
        expect(
            snapshot(pid: 100, windowID: 42, onScreen: false, visible: 0),
            target: target,
            result: .targetUnavailable
        )

        let movedMonitorSnapshot = snapshot(
            pid: 100,
            windowID: 42,
            onScreen: true,
            visible: 1,
            targetMonitorID: 2
        )
        let movedMonitorResult = FocusPolicy.evaluate(
            snapshot: movedMonitorSnapshot,
            target: target,
            minimumVisibleFraction: 0.65,
            requiredMonitorID: 1
        )
        guard movedMonitorResult == .differentMonitor else {
            fatalError("A target moved away from its selected monitor must pause focus")
        }

        let browserTarget = TrackedWindow(
            id: 91,
            ownerPID: 300,
            appName: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            title: "온라인 강의"
        )
        let changedTab = snapshot(pid: 300, windowID: 91, onScreen: true, visible: 1, windowTitle: "YouTube")
        expect(changedTab, target: browserTarget, result: .differentTab)

        let untitled = TrackedWindow(
            id: 7,
            ownerPID: 101,
            appName: "Browser",
            bundleIdentifier: "test.browser",
            title: ""
        )
        guard untitled.displayName == "Browser — 제목 없는 창 #7" else {
            fatalError("Untitled windows must remain selectable")
        }

        let ranking = LeaderboardCalculator.rankings(from: [
            session(name: "딴짓왕", focus: 20, distraction: 80, target: target),
            session(name: "집중왕", focus: 90, distraction: 10, target: target)
        ])
        guard ranking.map(\.name) == ["집중왕", "딴짓왕"] else {
            fatalError("Leaderboard must rank higher focus ratios first")
        }
        guard ranking.first?.name == "집중왕" else {
            fatalError("Focus ranking must keep the best participant first")
        }
        guard session(name: "나", focus: 20, distraction: 80, target: target)
            .activityNarrative.contains("Browser · Video에서 1분 20초") else {
            fatalError("Session history must preserve a readable activity trail")
        }

        print("Core focus policy checks passed")
    }

    private static func expect(_ snapshot: ActivitySnapshot, target: TrackedWindow, result: FocusStatus) {
        let actual = FocusPolicy.evaluate(snapshot: snapshot, target: target, minimumVisibleFraction: 0.65)
        guard actual == result else {
            fatalError("Expected \(result), got \(actual)")
        }
    }

    private static func snapshot(
        pid: Int32,
        windowID: UInt32,
        onScreen: Bool,
        visible: Double,
        targetMonitorID: UInt32? = nil,
        windowTitle: String = "Window"
    ) -> ActivitySnapshot {
        ActivitySnapshot(
            capturedAt: Date(),
            frontmostPID: pid,
            frontmostAppName: "Test",
            frontmostBundleIdentifier: "test.app",
            frontmostWindowID: windowID,
            frontmostWindowTitle: windowTitle,
            targetIsOnScreen: onScreen,
            targetVisibleFraction: visible,
            targetMonitorID: targetMonitorID
        )
    }

    private static func session(
        name: String,
        focus: TimeInterval,
        distraction: TimeInterval,
        target: TrackedWindow
    ) -> FocusSession {
        let end = Date()
        return FocusSession(
            id: UUID(),
            startedAt: end.addingTimeInterval(-(focus + distraction)),
            endedAt: end,
            participantName: name,
            plannedFocusSeconds: 100,
            completedFocusSeconds: focus,
            target: target,
            distractions: [
                DistractionEvent(
                    id: UUID(),
                    startedAt: end.addingTimeInterval(-distraction),
                    endedAt: end,
                    status: .differentApplication,
                    appName: "Browser",
                    bundleIdentifier: "test.browser",
                    windowTitle: "Video",
                    url: nil
                )
            ]
        )
    }
}
