import Foundation

/// Turns whatever the user typed into the command bar into a URL: either the
/// address itself, or a search with the configured engine.
enum URLResolver {
    private static let directSchemes: Set<String> = ["http", "https", "file", "about", "data", "blob"]

    static func resolve(_ input: String, engine: SearchEngine = Preferences.searchEngine) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return directURL(text) ?? engine.searchURL(for: text)
    }

    /// The URL `text` names, or nil when it reads like a search query.
    static func directURL(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), directSchemes.contains(scheme) {
            return url
        }
        guard looksLikeHost(text) else { return nil }
        return URL(string: (isLocal(text) ? "http://" : "https://") + text)
    }

    /// "example.com/path", "localhost:3000", "192.168.1.1" — but not "hello" or "what.is".
    private static func looksLikeHost(_ text: String) -> Bool {
        let pattern = #"^(localhost|\[[0-9a-fA-F:]+\]|[\w-]+(\.[\w-]+)+)(:\d{1,5})?([/?#].*)?$"#
        guard text.range(of: pattern, options: .regularExpression) != nil else { return false }

        let lower = text.lowercased()
        if lower.hasPrefix("localhost") || lower.hasPrefix("[") { return true }

        let host = text.split(whereSeparator: { "/?#:".contains($0) }).first.map(String.init) ?? text
        if isIPv4(host) { return true }
        guard let tld = host.split(separator: ".").last else { return false }
        return tld.count >= 2 && tld.allSatisfy { $0.isLetter }
    }

    private static func isLocal(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("localhost") || lower.hasPrefix("[::1]") { return true }
        let host = lower.split(whereSeparator: { "/?#:".contains($0) }).first.map(String.init) ?? lower
        return isIPv4(host)
    }

    private static func isIPv4(_ host: String) -> Bool {
        host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
    }

    /// "github.com" for https://www.github.com/foo — what the sidebar address pill shows.
    static func displayHost(_ url: URL?) -> String? {
        guard let url else { return nil }
        if url.isFileURL { return url.lastPathComponent }
        guard var host = url.host, !host.isEmpty else { return url.absoluteString }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}

/// Fetches search-as-you-type suggestions from the engine's OpenSearch endpoint.
enum SearchSuggestions {
    static func fetch(_ query: String, engine: SearchEngine) async -> [String] {
        guard let url = engine.suggestionsURL(for: query) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let response = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: response.0) as? [Any],
              json.count > 1,
              let list = json[1] as? [String]
        else { return [] }
        return list
    }
}
