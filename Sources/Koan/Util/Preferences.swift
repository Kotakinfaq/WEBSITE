import Foundation

/// The search engines offered in Settings. `%s` in a template is replaced by the
/// percent-encoded query.
enum SearchEngine: String, CaseIterable, Identifiable {
    case duckDuckGo, google, bing, kagi, ecosia, startpage

    var id: String { rawValue }

    var name: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .google: return "Google"
        case .bing: return "Bing"
        case .kagi: return "Kagi"
        case .ecosia: return "Ecosia"
        case .startpage: return "Startpage"
        }
    }

    private var searchTemplate: String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com/?q=%s"
        case .google: return "https://www.google.com/search?q=%s"
        case .bing: return "https://www.bing.com/search?q=%s"
        case .kagi: return "https://kagi.com/search?q=%s"
        case .ecosia: return "https://www.ecosia.org/search?q=%s"
        case .startpage: return "https://www.startpage.com/do/search?q=%s"
        }
    }

    /// Endpoints that answer in the OpenSearch suggestions format: `["query", ["a", "b", ...]]`.
    var suggestionsTemplate: String {
        switch self {
        case .google: return "https://suggestqueries.google.com/complete/search?client=firefox&q=%s"
        case .bing: return "https://api.bing.com/osjson.aspx?query=%s"
        default: return "https://duckduckgo.com/ac/?type=list&q=%s"
        }
    }

    func searchURL(for query: String) -> URL? {
        URL(string: searchTemplate.replacingOccurrences(of: "%s", with: Self.encode(query)))
    }

    func suggestionsURL(for query: String) -> URL? {
        URL(string: suggestionsTemplate.replacingOccurrences(of: "%s", with: Self.encode(query)))
    }

    private static func encode(_ query: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
    }
}

/// UserDefaults-backed settings. Views bind to the same keys with `@AppStorage`.
enum Preferences {
    enum Keys {
        static let searchEngine = "searchEngine"
        static let showSearchSuggestions = "showSearchSuggestions"
        static let unloadAfterMinutes = "unloadAfterMinutes"
        static let restoreSession = "restoreSession"
        static let compactMode = "compactMode"
        static let sidebarWidth = "sidebarWidth"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.searchEngine: SearchEngine.duckDuckGo.rawValue,
            Keys.showSearchSuggestions: true,
            Keys.unloadAfterMinutes: 30,
            Keys.restoreSession: true,
            Keys.compactMode: false,
            Keys.sidebarWidth: 250.0,
        ])
    }

    static var searchEngine: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: Keys.searchEngine) ?? "") ?? .duckDuckGo
    }

    static var showSearchSuggestions: Bool { UserDefaults.standard.bool(forKey: Keys.showSearchSuggestions) }
    static var unloadAfterMinutes: Int { UserDefaults.standard.integer(forKey: Keys.unloadAfterMinutes) }
    static var restoreSession: Bool { UserDefaults.standard.bool(forKey: Keys.restoreSession) }
    static var compactMode: Bool { UserDefaults.standard.bool(forKey: Keys.compactMode) }
}

enum AppPaths {
    /// ~/Library/Application Support/Koan
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Koan", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    /// ~/Library/Caches/Koan
    static let caches: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Koan", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
}
