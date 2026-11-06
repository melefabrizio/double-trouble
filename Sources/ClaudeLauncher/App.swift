import AppKit
import SwiftUI

@main
struct ClaudeLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = Store()
    @State private var codeStore = CodeStore()

    var body: some Scene {
        Window("Double Trouble", id: "main") {
            ContentView()
                .environment(store)
                .environment(codeStore)
                .frame(minWidth: 780, minHeight: 540)
                .task {
                    store.start()
                    codeStore.start()
                }
        }
        .defaultSize(width: 900, height: 620)
        .windowToolbarStyle(.unified)
        .commands {
            // Every toolbar command must also live in the menu bar (HIG, Toolbars > macOS).
            // ⌘N goes to the first installed product, ⌥⌘N to the second.
            CommandGroup(replacing: .newItem) {
                if store.claudeInstalled {
                    Button("Nuovo ambiente Claude Desktop…") {
                        NotificationCenter.default.post(name: .newEnvironment, object: EnvironmentKind.desktop)
                    }
                    .keyboardShortcut("n")
                }
                if codeStore.isInstalled {
                    Button("Nuovo ambiente Claude Code…") {
                        NotificationCenter.default.post(name: .newEnvironment, object: EnvironmentKind.code)
                    }
                    .keyboardShortcut("n", modifiers: store.claudeInstalled ? [.command, .option] : .command)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum EnvironmentKind { case desktop, code }

extension Notification.Name {
    static let newEnvironment = Notification.Name("newEnvironment")
}
