import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject private var store: BrowserStore
    @AppStorage(Preferences.Keys.searchEngine) private var searchEngine: SearchEngine = .duckDuckGo
    @AppStorage(Preferences.Keys.showSearchSuggestions) private var showSuggestions = true
    @AppStorage(Preferences.Keys.unloadAfterMinutes) private var unloadAfterMinutes = 30
    @AppStorage(Preferences.Keys.restoreSession) private var restoreSession = true
    @State private var confirmingClear = false
    @State private var cleared = false

    private var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var body: some View {
        Form {
            Section("Search") {
                Picker("Search engine", selection: $searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.name).tag(engine)
                    }
                }
                Toggle("Show search suggestions", isOn: $showSuggestions)
            }

            Section("Tabs") {
                Toggle("Restore tabs and workspaces on launch", isOn: $restoreSession)
                Picker("Unload inactive tabs after", selection: $unloadAfterMinutes) {
                    Text("Never").tag(0)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("3 hours").tag(180)
                }
            }

            Section("Privacy") {
                HStack {
                    Button("Clear Browsing Data…") { confirmingClear = true }
                    if cleared {
                        Text("Cleared").foregroundStyle(.secondary)
                    }
                }
                .confirmationDialog(
                    "Clear history, cookies, caches and website data?",
                    isPresented: $confirmingClear
                ) {
                    Button("Clear", role: .destructive) { clearBrowsingData() }
                }
            }

            Section("Default Browser") {
                Button("Make Koan the Default Browser") {
                    Task {
                        let app = Bundle.main.bundleURL
                        try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http")
                        try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "https")
                    }
                }
                .disabled(!isAppBundle)
                if !isAppBundle {
                    Text("Available when Koan runs from Koan.app (see scripts/build-app.sh).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func clearBrowsingData() {
        store.history.clear()
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}
        cleared = true
    }
}
