import AppKit
import SwiftUI

@main
struct KoanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = BrowserStore.shared

    init() {
        Preferences.registerDefaults()
    }

    var body: some Scene {
        Window("Koan", id: "browser") {
            BrowserWindow()
                .environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands { BrowserCommands(store: store) }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than Koan.app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        BrowserStore.shared.saveNow()
    }

    /// Links opened from other apps once Koan is the default browser.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            BrowserStore.shared.openTab(url: url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
