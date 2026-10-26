import Foundation

struct TabSnapshot: Codable {
    var id: UUID
    var url: URL?
    var title: String
    var isPinned: Bool
    var pinnedURL: URL?
    /// WebKit's opaque back/forward state, so history survives a relaunch.
    var interactionState: Data?
}

struct WorkspaceSnapshot: Codable {
    var id: UUID
    var name: String
    var icon: String
    var theme: WorkspaceTheme
    var tabs: [TabSnapshot]
    var selectedTabID: UUID?
    var split: SplitGroup?
}

struct SessionSnapshot: Codable {
    var version: Int
    var workspaces: [WorkspaceSnapshot]
    var essentials: [TabSnapshot]
    var activeWorkspaceID: UUID
}

/// Reads and writes the session file in Application Support.
enum SessionStore {
    private static let fileURL = AppPaths.support.appendingPathComponent("session.json")

    static func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(SessionSnapshot.self, from: data)
        } catch {
            NSLog("Koan: could not read session: \(error)")
            return nil
        }
    }

    static func save(_ snapshot: SessionSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Koan: could not save session: \(error)")
        }
    }
}
