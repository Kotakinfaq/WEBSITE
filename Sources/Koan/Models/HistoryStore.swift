import Foundation

/// Visited pages, used for command bar suggestions.
@MainActor
final class HistoryStore {
    struct Entry: Codable {
        var url: URL
        var title: String
        var lastVisited: Date
        var visitCount: Int
    }

    private var entries: [String: Entry] = [:]
    private var saveTask: Task<Void, Never>?
    private let fileURL = AppPaths.support.appendingPathComponent("history.json")
    private let maxEntries = 10_000

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([Entry].self, from: data) {
            for entry in list { entries[entry.url.absoluteString] = entry }
        }
    }

    func record(url: URL?, title: String) {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let key = url.absoluteString
        var entry = entries[key] ?? Entry(url: url, title: title, lastVisited: Date(), visitCount: 0)
        entry.visitCount += 1
        entry.lastVisited = Date()
        if !title.isEmpty { entry.title = title }
        entries[key] = entry
        trimIfNeeded()
        scheduleSave()
    }

    func updateTitle(_ title: String, for url: URL?) {
        guard let key = url?.absoluteString, entries[key] != nil, !title.isEmpty else { return }
        entries[key]?.title = title
        scheduleSave()
    }

    /// Entries containing every word of `query`, best first.
    func search(_ query: String, limit: Int) -> [Entry] {
        let terms = query.lowercased().split(separator: " ")
        guard !terms.isEmpty, limit > 0 else { return [] }
        let first = String(terms[0])
        let matches = entries.values.filter { entry in
            let haystack = (entry.title + " " + entry.url.absoluteString).lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
        return Array(matches.sorted { score($0, prefix: first) > score($1, prefix: first) }.prefix(limit))
    }

    func clear() {
        entries.removeAll()
        saveNow()
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            let data = try JSONEncoder().encode(Array(entries.values))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Koan: could not save history: \(error)")
        }
    }

    private func score(_ entry: Entry, prefix: String) -> Double {
        let days = max(Date().timeIntervalSince(entry.lastVisited) / 86_400, 0)
        var score = log2(Double(entry.visitCount) + 1) * 4 + 10 / (1 + days)
        let host = (entry.url.host ?? "").lowercased()
        if host.hasPrefix(prefix) || host.hasPrefix("www." + prefix) { score += 20 }
        return score
    }

    private func trimIfNeeded() {
        guard entries.count > maxEntries else { return }
        let oldest = entries.values.sorted { $0.lastVisited < $1.lastVisited }.prefix(entries.count - maxEntries + 500)
        for entry in oldest { entries.removeValue(forKey: entry.url.absoluteString) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
