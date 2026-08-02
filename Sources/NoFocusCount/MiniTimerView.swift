import AppKit
import SwiftUI

struct MiniTimerView: View {
    @ObservedObject var model: AppModel
    @State private var hovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.025, green: 0.028, blue: 0.032).opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(statusColor.opacity(hovered ? 0.45 : 0.18))
                }
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: statusColor, radius: 4)
                    Text(model.remainingFocusSeconds.clockText)
                        .font(.system(size: 37, weight: .medium, design: .monospaced).monospacedDigit())
                        .tracking(-2)
                        .contentTransition(.numericText())
                }
                .offset(y: hovered ? -8 : 0)

                HStack(spacing: 8) {
                    if model.currentSession != nil {
                        Button {
                            model.toggleManualPause()
                        } label: {
                            Image(systemName: model.phase == .pausedByUser ? "play.fill" : "pause.fill")
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.stopSession()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    Text(model.phase.label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .lineLimit(1)

                    Button {
                        closeMiniTimer()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
                .opacity(hovered ? 1 : 0)
                .offset(y: hovered ? -3 : 3)
                .allowsHitTesting(hovered)
            }
        }
        .frame(width: 236, height: 104)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.16), value: hovered)
        .onHover { hovered = $0 }
    }

    private func closeMiniTimer() {
        NSApp.windows.first { $0.identifier?.rawValue == MiniTimerPanelController.identifier }?.orderOut(nil)
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

@MainActor
final class MiniTimerPanelController: NSWindowController {
    static let identifier = "NoFocusCountMiniTimer"

    init(model: AppModel) {
        let size = NSSize(width: 236, height: 104)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier(Self.identifier)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: MiniTimerView(model: model))
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let panel = window else { return }
        if !panel.isVisible {
            let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
            let origin = NSPoint(
                x: visibleFrame.maxX - panel.frame.width - 24,
                y: visibleFrame.maxY - panel.frame.height - 24
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
    }
}
