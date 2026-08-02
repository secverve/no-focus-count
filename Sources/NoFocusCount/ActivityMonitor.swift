import AppKit
import ApplicationServices
import Foundation

final class ActivityMonitor {
    private struct WindowRecord {
        let id: UInt32
        let ownerPID: Int32
        let appName: String
        let bundleIdentifier: String?
        let title: String
        let bounds: CGRect
        let alpha: Double
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func availableWindows() -> [TrackedWindow] {
        windowRecords()
            .filter { $0.ownerPID != ProcessInfo.processInfo.processIdentifier }
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                TrackedWindow(
                    id: $0.id,
                    ownerPID: $0.ownerPID,
                    appName: $0.appName,
                    bundleIdentifier: $0.bundleIdentifier,
                    title: $0.title
                )
            }
    }

    func snapshot(for target: TrackedWindow) -> ActivitySnapshot {
        let windows = windowRecords()
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmostApplication?.processIdentifier
        let frontmostWindow = windows.first { $0.ownerPID == frontmostPID }
        let targetIndex = windows.firstIndex { $0.id == target.id }
        let visibleFraction = targetIndex.map { sampledVisibleFraction(of: windows[$0], at: $0, in: windows) } ?? 0

        return ActivitySnapshot(
            capturedAt: Date(),
            frontmostPID: frontmostPID,
            frontmostAppName: frontmostApplication?.localizedName ?? frontmostWindow?.appName ?? "알 수 없는 앱",
            frontmostBundleIdentifier: frontmostApplication?.bundleIdentifier ?? frontmostWindow?.bundleIdentifier,
            frontmostWindowID: frontmostWindow?.id,
            frontmostWindowTitle: focusedWindowTitle(pid: frontmostPID) ?? frontmostWindow?.title ?? "",
            targetIsOnScreen: targetIndex != nil,
            targetVisibleFraction: visibleFraction
        )
    }

    func browserURL(bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else { return nil }

        let script: String
        switch bundleIdentifier {
        case "com.apple.Safari":
            script = "tell application id \"com.apple.Safari\" to get URL of current tab of front window"
        case "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser", "com.microsoft.edgemac":
            script = "tell application id \"\(bundleIdentifier)\" to get URL of active tab of front window"
        default:
            return nil
        }

        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result?.stringValue
    }

    private func windowRecords() -> [WindowRecord] {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap { info in
            guard
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let number = info[kCGWindowNumber as String] as? UInt32,
                let pid = info[kCGWindowOwnerPID as String] as? Int32,
                let appName = info[kCGWindowOwnerName as String] as? String,
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary
            else { return nil }

            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary as CFDictionary, &bounds), bounds.width > 80, bounds.height > 60 else {
                return nil
            }

            let app = NSRunningApplication(processIdentifier: pid)
            return WindowRecord(
                id: number,
                ownerPID: pid,
                appName: appName,
                bundleIdentifier: app?.bundleIdentifier,
                title: info[kCGWindowName as String] as? String ?? "",
                bounds: bounds,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1
            )
        }
    }

    private func focusedWindowTitle(pid: Int32?) -> String? {
        guard let pid else { return nil }
        let application = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let window = focusedWindow else { return nil }

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else {
            return nil
        }
        return title as? String
    }

    private func sampledVisibleFraction(of target: WindowRecord, at index: Int, in windows: [WindowRecord]) -> Double {
        let columns = 12
        let rows = 8
        var visible = 0
        let total = columns * rows
        let coveringWindows = windows.prefix(index).filter { $0.alpha > 0.05 }

        for column in 0..<columns {
            for row in 0..<rows {
                let x = target.bounds.minX + target.bounds.width * (Double(column) + 0.5) / Double(columns)
                let y = target.bounds.minY + target.bounds.height * (Double(row) + 0.5) / Double(rows)
                let point = CGPoint(x: x, y: y)
                if !coveringWindows.contains(where: { $0.bounds.contains(point) }) {
                    visible += 1
                }
            }
        }

        return Double(visible) / Double(total)
    }
}
