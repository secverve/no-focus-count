import SwiftUI

@main
struct NoFocusCountApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("창 목록 새로고침") { model.refreshWindows() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
