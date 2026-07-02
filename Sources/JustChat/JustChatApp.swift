import SwiftUI

@main
struct JustChatApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .commands {
            CommandMenu("Just Chat") {
                Button("切换快捷助手") {
                    appState.toggleQuickAssistant()
                }

                Button("切换划词助手") {
                    appState.toggleSelectionAssistant()
                }
            }
        }

        MenuBarExtra(
            content: {
                Button("切换快捷助手") {
                    appState.toggleQuickAssistant()
                }
                Button("切换划词助手") {
                    appState.toggleSelectionAssistant()
                }
                Divider()
                Button("设置") {
                    appState.rootSection = .settings
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            },
            label: {
                Image(systemName: "message.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
        )
    }
}
