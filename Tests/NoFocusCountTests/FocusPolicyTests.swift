import XCTest
import AppKit
@testable import NoFocusCount

final class FocusPolicyTests: XCTestCase {
    private let target = TrackedWindow(
        id: 42,
        ownerPID: 100,
        appName: "Study App",
        bundleIdentifier: "test.study",
        title: "Chapter 1"
    )

    func testFocusedWhenTargetIsFrontmostAndVisible() {
        let snapshot = makeSnapshot(pid: 100, windowID: 42, isOnScreen: true, visible: 0.9)
        XCTAssertEqual(FocusPolicy.evaluate(snapshot: snapshot, target: target, minimumVisibleFraction: 0.65), .focused)
    }

    func testDifferentApplicationPausesFocus() {
        let snapshot = makeSnapshot(pid: 200, windowID: 50, isOnScreen: true, visible: 1)
        XCTAssertEqual(FocusPolicy.evaluate(snapshot: snapshot, target: target, minimumVisibleFraction: 0.65), .differentApplication)
    }

    func testDifferentWindowInSameApplicationPausesFocus() {
        let snapshot = makeSnapshot(pid: 100, windowID: 77, isOnScreen: true, visible: 1)
        XCTAssertEqual(FocusPolicy.evaluate(snapshot: snapshot, target: target, minimumVisibleFraction: 0.65), .differentWindow)
    }

    func testCoveredTargetPausesFocus() {
        let snapshot = makeSnapshot(pid: 100, windowID: 42, isOnScreen: true, visible: 0.3)
        XCTAssertEqual(FocusPolicy.evaluate(snapshot: snapshot, target: target, minimumVisibleFraction: 0.65), .targetCovered)
    }

    func testMissingTargetPausesFocus() {
        let snapshot = makeSnapshot(pid: 100, windowID: 42, isOnScreen: false, visible: 0)
        XCTAssertEqual(FocusPolicy.evaluate(snapshot: snapshot, target: target, minimumVisibleFraction: 0.65), .targetUnavailable)
    }

    func testTargetMovingOffSelectedMonitorPausesFocus() {
        let snapshot = ActivitySnapshot(
            capturedAt: Date(),
            frontmostPID: 100,
            frontmostAppName: "Study App",
            frontmostBundleIdentifier: "test.study",
            frontmostWindowID: 42,
            frontmostWindowTitle: "Chapter 1",
            targetIsOnScreen: true,
            targetVisibleFraction: 1,
            targetMonitorID: 2
        )
        XCTAssertEqual(
            FocusPolicy.evaluate(
                snapshot: snapshot,
                target: target,
                minimumVisibleFraction: 0.65,
                requiredMonitorID: 1
            ),
            .differentMonitor
        )
    }

    func testChangingBrowserTabInSameWindowPausesFocus() {
        let browser = TrackedWindow(
            id: 42,
            ownerPID: 100,
            appName: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            title: "온라인 강의"
        )
        let snapshot = ActivitySnapshot(
            capturedAt: Date(),
            frontmostPID: 100,
            frontmostAppName: "Chrome",
            frontmostBundleIdentifier: "com.google.Chrome",
            frontmostWindowID: 42,
            frontmostWindowTitle: "YouTube",
            targetIsOnScreen: true,
            targetVisibleFraction: 1
        )
        XCTAssertEqual(
            FocusPolicy.evaluate(snapshot: snapshot, target: browser, minimumVisibleFraction: 0.65),
            .differentTab
        )
    }

    func testSessionNarrativeKeepsWindowAndDuration() {
        let session = makeSession(name: "나", focus: 60, distraction: 120)
        XCTAssertTrue(session.activityNarrative.contains("Browser · Video"))
        XCTAssertTrue(session.activityNarrative.contains("2분"))
    }

    func testRunningChromeWindowsRemainSelectable() throws {
        let chromeIsRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.google.Chrome"
        }
        guard chromeIsRunning else { throw XCTSkip("Chrome is not running on this machine") }

        let chromeWindows = ActivityMonitor().availableWindows().filter {
            $0.bundleIdentifier == "com.google.Chrome"
        }
        XCTAssertFalse(chromeWindows.isEmpty, "Chrome is running but no Chrome windows were exposed")
        XCTAssertTrue(chromeWindows.allSatisfy { $0.identityLabel.contains("창 #") })
    }

    func testLeaderboardOrdersHigherFocusRatioFirst() {
        let focused = makeSession(name: "집중왕", focus: 90, distraction: 10)
        let distracted = makeSession(name: "딴짓왕", focus: 20, distraction: 80)

        let ranking = LeaderboardCalculator.rankings(from: [distracted, focused])

        XCTAssertEqual(ranking.map(\.name), ["집중왕", "딴짓왕"])
    }

    private func makeSession(name: String, focus: TimeInterval, distraction: TimeInterval) -> FocusSession {
        FocusSession(
            id: UUID(),
            startedAt: Date(),
            endedAt: Date(),
            participantName: name,
            plannedFocusSeconds: 100,
            completedFocusSeconds: focus,
            target: target,
            distractions: [
                DistractionEvent(
                    id: UUID(),
                    startedAt: Date(timeIntervalSinceNow: -distraction),
                    endedAt: Date(),
                    status: .differentApplication,
                    appName: "Browser",
                    bundleIdentifier: "test.browser",
                    windowTitle: "Video",
                    url: nil
                )
            ]
        )
    }

    private func makeSnapshot(
        pid: Int32,
        windowID: UInt32,
        isOnScreen: Bool,
        visible: Double
    ) -> ActivitySnapshot {
        ActivitySnapshot(
            capturedAt: Date(),
            frontmostPID: pid,
            frontmostAppName: "Test",
            frontmostBundleIdentifier: "test.app",
            frontmostWindowID: windowID,
            frontmostWindowTitle: "Window",
            targetIsOnScreen: isOnScreen,
            targetVisibleFraction: visible
        )
    }
}
