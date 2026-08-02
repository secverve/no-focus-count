import XCTest
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

    func testCoveredTargetPausesFocus() {
        let snapshot = makeSnapshot(pid: 100, windowID: 42, isOnScreen: true, visible: 0.3)
        XCTAssertEqual(FocusPolicy.evaluate(snapshot: snapshot, target: target, minimumVisibleFraction: 0.65), .targetCovered)
    }

    func testMissingTargetPausesFocus() {
        let snapshot = makeSnapshot(pid: 100, windowID: 42, isOnScreen: false, visible: 0)
        XCTAssertEqual(FocusPolicy.evaluate(snapshot: snapshot, target: target, minimumVisibleFraction: 0.65), .targetUnavailable)
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
