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
            snapshot(pid: 100, windowID: 42, onScreen: true, visible: 0.3),
            target: target,
            result: .targetCovered
        )
        expect(
            snapshot(pid: 100, windowID: 42, onScreen: false, visible: 0),
            target: target,
            result: .targetUnavailable
        )

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
        visible: Double
    ) -> ActivitySnapshot {
        ActivitySnapshot(
            capturedAt: Date(),
            frontmostPID: pid,
            frontmostAppName: "Test",
            frontmostBundleIdentifier: "test.app",
            frontmostWindowID: windowID,
            frontmostWindowTitle: "Window",
            targetIsOnScreen: onScreen,
            targetVisibleFraction: visible
        )
    }
}
