import AppKit

/// Site icons by host, kept in memory and on disk so unloaded and restored
/// tabs still show their icon.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()

    private var memory: [String: NSImage] = [:]
    private var fetchedThisSession: Set<String> = []
    private let directory: URL

    private init() {
        directory = AppPaths.caches.appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cached(forHost host: String?) -> NSImage? {
        guard let host, !host.isEmpty else { return nil }
        if let image = memory[host] { return image }
        guard let data = try? Data(contentsOf: fileURL(for: host)), let image = NSImage(data: data) else { return nil }
        memory[host] = image
        return image
    }

    /// Downloads `iconURL` once per session per host.
    func fetch(_ iconURL: URL, host: String) async -> NSImage? {
        if fetchedThisSession.contains(host) { return memory[host] }
        fetchedThisSession.insert(host)

        var request = URLRequest(url: iconURL)
        request.timeoutInterval = 10
        guard let response = try? await URLSession.shared.data(for: request) else {
            fetchedThisSession.remove(host)
            return memory[host]
        }
        let status = (response.1 as? HTTPURLResponse)?.statusCode ?? 200
        guard status < 400, let image = NSImage(data: response.0), image.isValid else { return memory[host] }

        memory[host] = image
        try? response.0.write(to: fileURL(for: host), options: .atomic)
        return image
    }

    private func fileURL(for host: String) -> URL {
        directory.appendingPathComponent(host.replacingOccurrences(of: "/", with: "_"))
    }
}
