import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class FocusReceiptCapture {
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = base
            .appendingPathComponent("NoFocusCount", isDirectory: true)
            .appendingPathComponent("FocusReceipts", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func capture(windowID: UInt32, eventID: UUID) async -> String? {
        guard hasPermission else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let aspectRatio = max(0.2, window.frame.height / max(1, window.frame.width))
            configuration.width = 480
            configuration.height = max(120, Int(480 * aspectRatio))
            configuration.scalesToFit = true
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return save(image: image, eventID: eventID)
        } catch {
            return nil
        }
    }

    func deleteAll() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension.lowercased() == "jpg" {
            try? fileManager.removeItem(at: file)
        }
    }

    private func save(image: CGImage, eventID: UUID) -> String? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.58]
        ) else { return nil }

        let fileURL = directoryURL.appendingPathComponent("\(eventID.uuidString).jpg")
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            return nil
        }
    }
}
