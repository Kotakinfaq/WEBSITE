import SwiftUI

/// The two-color gradient a workspace paints behind the window.
struct WorkspaceTheme: Codable, Hashable {
    var primary: String
    var secondary: String

    var primaryColor: Color { Color(hex: primary) }
    var secondaryColor: Color { Color(hex: secondary) }

    var gradient: LinearGradient {
        LinearGradient(colors: [primaryColor, secondaryColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let presets: [WorkspaceTheme] = [
        WorkspaceTheme(primary: "#A8C5A0", secondary: "#E3EFD9"), // sage
        WorkspaceTheme(primary: "#8EC5FC", secondary: "#E0C3FC"), // ocean
        WorkspaceTheme(primary: "#FFB199", secondary: "#FFE29F"), // peach
        WorkspaceTheme(primary: "#C3B1E1", secondary: "#F1E4F3"), // lavender
        WorkspaceTheme(primary: "#96E6A1", secondary: "#D4FC79"), // mint
        WorkspaceTheme(primary: "#FA709A", secondary: "#FEE140"), // sunset
        WorkspaceTheme(primary: "#89F7FE", secondary: "#66A6FF"), // sky
        WorkspaceTheme(primary: "#F6D5F7", secondary: "#FBE9D7"), // rose
        WorkspaceTheme(primary: "#8E9EAB", secondary: "#EEF2F3"), // slate
        WorkspaceTheme(primary: "#434343", secondary: "#1F1C2C"), // midnight
    ]
}

/// Two to four tabs shown side by side. `fractions` are each pane's share of the space.
struct SplitGroup: Codable, Hashable {
    enum Axis: String, Codable { case horizontal, vertical }

    var tabIDs: [UUID]
    var axis: Axis = .horizontal
    var fractions: [Double]

    init(tabIDs: [UUID], axis: Axis = .horizontal) {
        self.tabIDs = tabIDs
        self.axis = axis
        self.fractions = Self.equal(tabIDs.count)
    }

    static let maxPanes = 4
    private static let minFraction = 0.15

    static func equal(_ count: Int) -> [Double] {
        count > 0 ? Array(repeating: 1 / Double(count), count: count) : []
    }

    static func normalized(_ fractions: [Double], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard fractions.count == count, !fractions.contains(where: { $0 <= 0 }) else { return equal(count) }
        let sum = fractions.reduce(0, +)
        return fractions.map { $0 / sum }
    }

    /// Moves the divider after pane `index` by `delta` (a share of the total length).
    static func adjust(_ fractions: [Double], at index: Int, delta: Double) -> [Double] {
        guard fractions.indices.contains(index + 1) else { return fractions }
        var result = fractions
        let pair = fractions[index] + fractions[index + 1]
        let first = min(max(fractions[index] + delta, minFraction), pair - minFraction)
        result[index] = first
        result[index + 1] = pair - first
        return result
    }
}

/// A named space with its own tabs, pinned tabs and theme. Essentials live on
/// the store and are shared by every workspace.
@MainActor
final class Workspace: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var icon: String
    @Published var theme: WorkspaceTheme
    /// Pinned tabs first, then regular tabs.
    @Published var tabs: [BrowserTab]
    @Published var selectedTabID: UUID?
    @Published var split: SplitGroup?

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        theme: WorkspaceTheme,
        tabs: [BrowserTab] = [],
        selectedTabID: UUID? = nil,
        split: SplitGroup? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.theme = theme
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.split = split
    }

    var pinnedTabs: [BrowserTab] { tabs.filter { $0.isPinned } }
    var regularTabs: [BrowserTab] { tabs.filter { !$0.isPinned } }

    var displayIcon: String { icon.isEmpty ? "•" : icon }

    func contains(_ tab: BrowserTab) -> Bool { tabs.contains { $0 === tab } }

    /// Keeps pinned tabs ahead of regular ones without disturbing either group's order.
    func normalizeOrder() {
        let ordered = pinnedTabs + regularTabs
        if ordered.map({ $0.id }) != tabs.map({ $0.id }) { tabs = ordered }
    }

    static let suggestedIcons = [
        "🌿", "🏠", "💼", "🎨", "📚", "🎮", "🎵", "🧪", "✈️", "🛒",
        "💡", "🔥", "🌊", "🌙", "☕️", "🧘", "💻", "📷", "🍀", "⭐️",
    ]
}
