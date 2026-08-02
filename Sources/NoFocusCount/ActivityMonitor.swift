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
        let isOnScreen: Bool
        let monitorID: UInt32?
        let monitorName: String?
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func availableWindows() -> [TrackedWindow] {
        windowRecords(onScreenOnly: false, enrichTitles: true)
            .filter { $0.ownerPID != ProcessInfo.processInfo.processIdentifier }
            .filter {
                NSRunningApplication(processIdentifier: $0.ownerPID)?.activationPolicy == .regular
            }
            .sorted {
                if $0.isOnScreen != $1.isOnScreen { return $0.isOnScreen && !$1.isOnScreen }
                if $0.appName != $1.appName { return $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
                return $0.id < $1.id
            }
            .map {
                TrackedWindow(
                    id: $0.id,
                    ownerPID: $0.ownerPID,
                    appName: $0.appName,
                    bundleIdentifier: $0.bundleIdentifier,
                    title: $0.title,
                    monitorID: $0.monitorID,
                    monitorName: $0.monitorName,
                    isOnScreen: $0.isOnScreen
                )
            }
    }

    func availableDisplays() -> [TrackedDisplay] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else { return [] }

        return displayIDs.prefix(Int(count)).enumerated().map { index, displayID in
            let screenName = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
            })?.localizedName
            return TrackedDisplay(
                id: displayID,
                name: screenName ?? "모니터 \(index + 1)",
                bounds: CGDisplayBounds(displayID),
                isMain: displayID == CGMainDisplayID()
            )
        }
        .sorted {
            if $0.isMain != $1.isMain { return $0.isMain }
            return $0.bounds.minX < $1.bounds.minX
        }
    }

    func frontmostWindow() -> TrackedWindow? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular else { return nil }
        let records = windowRecords(onScreenOnly: true, enrichTitles: true).filter {
            $0.ownerPID == application.processIdentifier
        }
        let focusedTitle = focusedWindowTitle(pid: application.processIdentifier)
        guard let record = records.first(where: {
            !$0.title.isEmpty && $0.title == focusedTitle
        }) ?? records.first else { return nil }
        return TrackedWindow(
            id: record.id,
            ownerPID: record.ownerPID,
            appName: record.appName,
            bundleIdentifier: record.bundleIdentifier,
            title: record.title,
            monitorID: record.monitorID,
            monitorName: record.monitorName,
            isOnScreen: record.isOnScreen
        )
    }

    func snapshot(for target: TrackedWindow) -> ActivitySnapshot {
        let windows = windowRecords(onScreenOnly: true, enrichTitles: false)
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmostApplication?.processIdentifier
        let focusedTitle = focusedWindowTitle(pid: frontmostPID)
        let frontmostWindows = windows.filter { $0.ownerPID == frontmostPID }
        let frontmostWindow = frontmostWindows.first {
            !($0.title.isEmpty) && $0.title == focusedTitle
        } ?? frontmostWindows.first
        let targetIndex = windows.firstIndex { $0.id == target.id }
        let visibleFraction = targetIndex.map { sampledVisibleFraction(of: windows[$0], at: $0, in: windows) } ?? 0

        return ActivitySnapshot(
            capturedAt: Date(),
            frontmostPID: frontmostPID,
            frontmostAppName: frontmostApplication?.localizedName ?? frontmostWindow?.appName ?? "알 수 없는 앱",
            frontmostBundleIdentifier: frontmostApplication?.bundleIdentifier ?? frontmostWindow?.bundleIdentifier,
            frontmostWindowID: frontmostWindow?.id,
            frontmostWindowTitle: focusedTitle ?? frontmostWindow?.title ?? "",
            targetIsOnScreen: targetIndex != nil,
            targetVisibleFraction: visibleFraction,
            targetMonitorID: targetIndex.flatMap { windows[$0].monitorID },
            frontmostMonitorName: frontmostWindow?.monitorName,
            frontmostMonitorID: frontmostWindow?.monitorID
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

    private func windowRecords(onScreenOnly: Bool, enrichTitles: Bool) -> [WindowRecord] {
        let displays = availableDisplays()
        let options: CGWindowListOption = onScreenOnly
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(
            options,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let records = rawWindows.compactMap { info -> WindowRecord? in
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
            let display = display(containing: bounds, in: displays)
            return WindowRecord(
                id: number,
                ownerPID: pid,
                appName: appName,
                bundleIdentifier: app?.bundleIdentifier,
                title: info[kCGWindowName as String] as? String ?? "",
                bounds: bounds,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
                isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false,
                monitorID: display?.id,
                monitorName: display?.name
            )
        }
        return enrichTitles ? enrichMissingTitles(in: records) : records
    }

    private func enrichMissingTitles(in records: [WindowRecord]) -> [WindowRecord] {
        let missingPIDs = Set(records.filter { $0.title.isEmpty }.map(\.ownerPID))
        let accessibleByPID = Dictionary(uniqueKeysWithValues: missingPIDs.map {
            ($0, accessibilityWindows(pid: $0))
        })
        return records.map { record in
            guard record.title.isEmpty,
                  let candidates = accessibleByPID[record.ownerPID],
                  let match = candidates.min(by: {
                      boundsDistance($0.bounds, record.bounds) < boundsDistance($1.bounds, record.bounds)
                  }),
                  boundsDistance(match.bounds, record.bounds) < 28 else { return record }
            return WindowRecord(
                id: record.id,
                ownerPID: record.ownerPID,
                appName: record.appName,
                bundleIdentifier: record.bundleIdentifier,
                title: match.title,
                bounds: record.bounds,
                alpha: record.alpha,
                isOnScreen: record.isOnScreen,
                monitorID: record.monitorID,
                monitorName: record.monitorName
            )
        }
    }

    private func accessibilityWindows(pid: Int32) -> [(title: String, bounds: CGRect)] {
        let application = AXUIElementCreateApplication(pid)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement] else { return [] }
        return windows.compactMap { window in
            var rawTitle: CFTypeRef?
            var rawPosition: CFTypeRef?
            var rawSize: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &rawTitle) == .success,
                  let title = rawTitle as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &rawPosition) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &rawSize) == .success,
                  let position = point(from: rawPosition),
                  let size = size(from: rawSize) else { return nil }
            return (title, CGRect(origin: position, size: size))
        }
    }

    private func point(from value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func size(from value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func boundsDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }

    private func display(containing bounds: CGRect, in displays: [TrackedDisplay]) -> TrackedDisplay? {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return displays.first { $0.bounds.contains(center) }
            ?? displays.max { lhs, rhs in
                intersectionArea(lhs.bounds, bounds) < intersectionArea(rhs.bounds, bounds)
            }
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
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
