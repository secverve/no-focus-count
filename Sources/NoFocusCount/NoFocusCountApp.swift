import SwiftUI

@main
struct NoFocusCountApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear {
                    if model.alarmEnabled {
                        model.requestAlarmPermission()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 820, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("창 목록 새로고침") { model.refreshWindows() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

    }
}
