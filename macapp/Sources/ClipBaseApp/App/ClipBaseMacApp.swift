import AppKit
import SwiftUI

@main
struct ClipBaseMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ClipBaseStore()

    var body: some Scene {
        WindowGroup("ClipBase", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandMenu("ClipBase") {
                Button("立即同步") {
                    Task { await store.syncNow() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("匯入 CSV...") {
                    store.openCSVImportPanel()
                }
                Button("匯出 CSV...") {
                    store.openCSVExportPanel()
                }

                Divider()

                Button("登出") {
                    Task { await store.logout() }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
