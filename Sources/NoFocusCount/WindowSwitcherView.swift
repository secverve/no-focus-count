import AppKit
import SwiftUI

@MainActor
final class WindowSwitcherPanelController: NSWindowController, NSWindowDelegate {
    private weak var model: AppModel?
    private var keyboardMonitor: Any?

    init(model: AppModel) {
        self.model = model
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 590),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "집중 창 선택기"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 620, height: 460)

        super.init(window: panel)
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: WindowSwitcherView(model: model) { [weak self] in
                self?.closeSwitcher()
            }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(on displayID: UInt32?) {
        move(on: displayID)
        installKeyboardMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func move(on displayID: UInt32?) {
        guard let window else { return }
        let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let width = min(940, max(620, visibleFrame.width - 48))
        let height = min(590, max(460, visibleFrame.height - 48))
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    func closeSwitcher() {
        removeKeyboardMonitor()
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyboardMonitor()
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true, let model = self.model else { return event }
            switch event.keyCode {
            case 48:
                model.stepSwitcherSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
                return nil
            case 123:
                model.stepSwitcherSelection(by: -1)
                return nil
            case 124:
                model.stepSwitcherSelection(by: 1)
                return nil
            case 36, 76:
                model.confirmSwitcherSelection()
                return nil
            case 53:
                self.closeSwitcher()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }
}

private struct WindowSwitcherView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var previews: [UInt32: NSImage] = [:]

    private var candidates: [TrackedWindow] {
        model.windowsOnSelectedDisplay
    }

    private var previewTaskID: String {
        "\(model.selectedMonitorID ?? 0):" + candidates.map { String($0.id) }.joined(separator: ",")
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [Color.black.opacity(0.66), Color.black.opacity(0.46)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 18) {
                header
                monitorStrip
                windowCarousel
                footer
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .task(id: previewTaskID) {
            previews = [:]
            previews = await model.windowPreviews(for: Array(candidates.prefix(16)))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.nfcLime)
            VStack(alignment: .leading, spacing: 3) {
                Text("집중 창 선택기")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("모니터를 고른 뒤 Tab 또는 ← → 로 창을 넘기고 Enter로 선택")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("닫기 (Esc)")
        }
    }

    private var monitorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(model.displays) { display in
                    let selected = model.selectedMonitorID == display.id
                    Button {
                        model.selectDisplay(display)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: selected ? "display.and.arrow.down" : "display")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(display.displayName)
                                    .font(.caption.weight(.semibold))
                                Text("\(display.resolutionLabel) · 창 \(model.windows.filter { $0.monitorID == display.id }.count)개")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 48)
                        .background(selected ? Color.nfcLime.opacity(0.13) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(selected ? Color.nfcLime.opacity(0.72) : Color.white.opacity(0.08), lineWidth: selected ? 1.2 : 0.7)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var windowCarousel: some View {
        if candidates.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "macwindow.badge.xmark")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
                Text("이 모니터에서 선택할 창을 찾지 못했습니다")
                    .font(.headline)
                Text("원하는 창을 이 모니터로 옮긴 뒤 새로고침해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("새로고침") { model.refreshWindows() }
                    .buttonStyle(NFCPillButtonStyle(primary: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(candidates) { window in
                            windowCard(window)
                                .id(window.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
                .onChange(of: model.switcherWindowID) { _, windowID in
                    guard let windowID else { return }
                    withAnimation(.snappy(duration: 0.22)) {
                        proxy.scrollTo(windowID, anchor: .center)
                    }
                }
            }
        }
    }

    private func windowCard(_ window: TrackedWindow) -> some View {
        let selected = model.switcherWindowID == window.id
        return Button {
            model.switcherWindowID = window.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.black.opacity(0.32))
                    if let image = previews[window.id] {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    } else {
                        VStack(spacing: 9) {
                            appIcon(for: window, size: 52)
                            Text(model.screenCaptureTrusted ? "미리보기 불러오는 중" : "미리보기 권한 없음")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 190)
                .clipped()

                HStack(alignment: .top, spacing: 9) {
                    appIcon(for: window, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(window.appName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "제목 없는 창 #\(window.id)" : window.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                        Text("창 #\(window.id)\(window.isOnScreen == false ? " · 최소화/다른 Space" : " · 현재 화면")")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(window.isOnScreen == false ? Color.orange : Color.secondary)
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.nfcLime)
                    }
                }
            }
            .padding(10)
            .frame(width: 286, height: 286, alignment: .top)
            .background(selected ? Color.white.opacity(0.105) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? Color.nfcLime : Color.white.opacity(0.08), lineWidth: selected ? 2 : 0.8)
            }
            .scaleEffect(selected ? 1 : 0.965)
            .shadow(color: selected ? Color.nfcLime.opacity(0.12) : .clear, radius: 20)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            model.switcherWindowID = window.id
            model.confirmSwitcherSelection()
        })
        .animation(.easeOut(duration: 0.16), value: selected)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !model.screenCaptureTrusted {
                Button {
                    model.requestScreenCapturePermission()
                } label: {
                    Label("창 미리보기 권한", systemImage: "rectangle.inset.filled.badge.record")
                }
                .buttonStyle(NFCPillButtonStyle())
            }
            Button {
                model.refreshWindows()
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .buttonStyle(NFCPillButtonStyle())

            Spacer()
            Text("ESC 닫기  ·  TAB 이동  ·  ENTER 선택")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            Button("이 창으로 집중") {
                model.confirmSwitcherSelection()
            }
            .buttonStyle(NFCPillButtonStyle(primary: true))
            .disabled(model.switcherWindowID == nil)
        }
    }

    @ViewBuilder
    private func appIcon(for window: TrackedWindow, size: CGFloat) -> some View {
        if let icon = NSRunningApplication(processIdentifier: window.ownerPID)?.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "macwindow")
                .font(.system(size: size * 0.52))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}
