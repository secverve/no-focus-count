import AppKit
import SwiftUI

struct MiniTimerView: View {
    @ObservedObject var model: AppModel
    @State private var hovered = false
    @State private var dragOffset: NSPoint?

    var body: some View {
        ZStack(alignment: .top) {
            glassSurface

            Capsule()
                .fill(Color.white.opacity(0.36))
                .frame(width: 34, height: 4)
                .padding(.top, 9)
                .opacity(hovered ? 1 : 0)

            VStack(spacing: 3) {
                Text(model.remainingFocusSeconds.clockText)
                    .font(.system(size: 43, weight: .semibold, design: .rounded).monospacedDigit())
                    .tracking(-2.5)
                    .foregroundStyle(Color.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.72), radius: 3, y: 1)
                    .contentTransition(.numericText())
                Text(selectedWindowLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .shadow(color: .black.opacity(0.85), radius: 2, y: 1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 250)
                    .help(selectedWindowLabel)
            }
            .padding(.horizontal, 14)
            .offset(y: hovered ? -13 : 0)

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor.opacity(0.8), radius: 4)
                    Text(model.phase.label.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.white.opacity(0.08), in: Capsule())

                if model.currentSession != nil {
                    Button {
                        model.toggleManualPause()
                    } label: {
                        Image(systemName: model.phase == .pausedByUser ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(MiniGlassButtonStyle())

                    Button {
                        model.stopSession()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(MiniGlassButtonStyle())
                }

                Button {
                    openMainWindow()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(MiniGlassButtonStyle())
                .help("설정 열기")

                Button {
                    closeMiniTimer()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(MiniGlassButtonStyle())
                .help("타이머 숨기기")
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 11)
            .opacity(hovered ? 1 : 0)
            .offset(y: hovered ? 0 : 4)
            .allowsHitTesting(hovered)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(width: 292, height: 126)
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.22), value: hovered)
        .onHover { hovered = $0 }
        .simultaneousGesture(windowDragGesture)
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in
                guard let panel = NSApp.windows.first(where: {
                    $0.identifier?.rawValue == MiniTimerPanelController.identifier
                }) else { return }
                let mouse = NSEvent.mouseLocation
                if dragOffset == nil {
                    dragOffset = NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
                }
                guard let dragOffset else { return }
                panel.setFrameOrigin(NSPoint(x: mouse.x - dragOffset.x, y: mouse.y - dragOffset.y))
            }
            .onEnded { _ in dragOffset = nil }
    }

    private var glassSurface: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.42), Color.white.opacity(0.08), statusColor.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .opacity(hovered ? 1 : 0)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first {
            $0.identifier?.rawValue != MiniTimerPanelController.identifier && !($0 is NSPanel)
        }?.makeKeyAndOrderFront(nil)
    }

    private func closeMiniTimer() {
        NSApp.windows.first { $0.identifier?.rawValue == MiniTimerPanelController.identifier }?.orderOut(nil)
    }

    private var selectedWindowLabel: String {
        guard let target = model.currentSession?.target ?? model.selectedWindow else {
            return "집중 창 미선택"
        }
        let title = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "\(target.appName) · 창 #\(target.id)" : "\(target.appName) · \(title)"
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

private struct MiniGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.62 : 0.9))
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08), in: Circle())
            .overlay { Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.7) }
    }
}

@MainActor
final class MiniTimerPanelController: NSWindowController {
    static let identifier = "NoFocusCountMiniTimer"
    private static let frameAutosaveName = "NoFocusCountMiniTimerFrame"
    private var hoverTrackingTimer: Timer?

    init(model: AppModel) {
        let size = NSSize(width: 292, height: 126)
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
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: MiniTimerView(model: model))
        if !panel.setFrameUsingName(Self.frameAutosaveName) {
            let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
            panel.setFrameOrigin(NSPoint(
                x: visibleFrame.maxX - panel.frame.width - 24,
                y: visibleFrame.maxY - panel.frame.height - 24
            ))
        }
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let panel = window else { return }
        panel.orderFrontRegardless()
        startHoverTracking()
    }

    private func startHoverTracking() {
        guard hoverTrackingTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let panel = self?.window, panel.isVisible else { return }
                panel.ignoresMouseEvents = !panel.frame.contains(NSEvent.mouseLocation)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTrackingTimer = timer
    }
}
