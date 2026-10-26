import AppKit
import SwiftUI
import WebKit

enum CommandBarMode {
    /// Opens the result in a new tab (⌘T).
    case newTab
    /// Navigates the current tab (⌘L, or clicking the address pill).
    case navigate
}

struct CommandBarRequest: Identifiable {
    let id = UUID()
    let mode: CommandBarMode
    let initialText: String
}

struct GlanceState {
    let tab: BrowserTab
    let parentID: UUID?
}

/// Where a tab dragged in the sidebar should land.
enum TabDropTarget {
    case essentials(before: BrowserTab?)
    case pinned(before: BrowserTab?)
    case regular(before: BrowserTab?)
    case workspace(Workspace)
}

struct Suggestion: Identifiable {
    enum Action {
        case open(URL)
        case switchTo(BrowserTab)
    }

    let id: String
    let icon: String
    var favicon: NSImage?
    let title: String
    let subtitle: String?
    var badge: String?
    let action: Action
}

private struct ClosedTabRecord {
    let url: URL?
    let title: String
    let workspaceID: UUID?
    let index: Int
    let isPinned: Bool
    let pinnedURL: URL?
    let wasEssential: Bool
    let interactionState: Data?
}

@MainActor
final class BrowserStore: ObservableObject {
    static let shared = BrowserStore()

    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var essentials: [BrowserTab] = []
    @Published private(set) var activeWorkspaceID: UUID
    @Published var isCompact: Bool {
        didSet {
            UserDefaults.standard.set(isCompact, forKey: Preferences.Keys.compactMode)
            if !isCompact { isCompactSidebarRevealed = false }
            updateWindowChrome()
        }
    }
    @Published var isCompactSidebarRevealed = false {
        didSet { updateWindowChrome() }
    }
    @Published private(set) var commandBar: CommandBarRequest?
    @Published private(set) var glance: GlanceState?
    @Published var editingWorkspace: Workspace?
    @Published private(set) var isFindBarVisible = false
    @Published var findQuery = ""
    @Published private(set) var findHasMatch = true
    @Published private(set) var findFocusRequest = 0

    let history = HistoryStore()
    let downloads = DownloadManager()

    private var closedTabs: [ClosedTabRecord] = []
    private weak var window: NSWindow?
    private var saveTask: Task<Void, Never>?
    private var unloadTimer: Timer?
    private var keyMonitor: Any?

    private init() {
        Preferences.registerDefaults()
        activeWorkspaceID = UUID()
        isCompact = Preferences.compactMode

        if Preferences.restoreSession, let snapshot = SessionStore.load() {
            restore(snapshot)
        }
        if workspaces.isEmpty {
            let home = Workspace(name: "Home", icon: "🌿", theme: WorkspaceTheme.presets[0])
            workspaces = [home]
            activeWorkspaceID = home.id
        }
        currentTab?.ensureWebView()
        startUnloadTimer()
    }

    // MARK: Lookup

    var activeWorkspace: Workspace {
        workspaces.first { $0.id == activeWorkspaceID } ?? workspaces[0]
    }

    var currentTab: BrowserTab? {
        activeWorkspace.selectedTabID.flatMap { tab(withID: $0) }
    }

    var allTabs: [BrowserTab] {
        essentials + workspaces.flatMap { $0.tabs }
    }

    /// Essentials, then the active workspace's tabs, in sidebar order.
    var visibleTabs: [BrowserTab] {
        essentials + activeWorkspace.tabs
    }

    func tab(withID id: UUID) -> BrowserTab? {
        if let tab = essentials.first(where: { $0.id == id }) { return tab }
        for workspace in workspaces {
            if let tab = workspace.tabs.first(where: { $0.id == id }) { return tab }
        }
        if let glance, glance.tab.id == id { return glance.tab }
        return nil
    }

    func isEssential(_ tab: BrowserTab) -> Bool {
        essentials.contains { $0 === tab }
    }

    func workspace(containing tab: BrowserTab) -> Workspace? {
        workspaces.first { $0.contains(tab) }
    }

    func isInActiveSplit(_ tab: BrowserTab) -> Bool {
        activeWorkspace.split?.tabIDs.contains(tab.id) ?? false
    }

    // MARK: Selecting & opening

    func select(_ tab: BrowserTab, focus: Bool = true) {
        if !isEssential(tab), let owner = workspace(containing: tab), owner.id != activeWorkspaceID {
            activeWorkspaceID = owner.id
        }
        let workspace = activeWorkspace
        if workspace.selectedTabID != tab.id { workspace.selectedTabID = tab.id }
        tab.lastActive = Date()
        tab.ensureWebView()
        if focus { focusWebView(of: tab) }
        setNeedsSave()
    }

    @discardableResult
    func openTab(url: URL?, relatedTo opener: BrowserTab? = nil, background: Bool = false) -> BrowserTab {
        let tab = BrowserTab(url: url)
        insert(tab, after: opener)
        if background {
            tab.lastActive = Date().addingTimeInterval(-1)
            tab.ensureWebView()
        } else {
            select(tab)
        }
        return tab
    }

    func openPopup(configuration: WKWebViewConfiguration, from opener: BrowserTab) -> BrowserTab {
        if glance?.tab === opener { glance = nil }
        let tab = BrowserTab(configuration: configuration, store: self)
        insert(tab, after: opener)
        select(tab)
        return tab
    }

    private func insert(_ tab: BrowserTab, after opener: BrowserTab?) {
        tab.store = self
        let workspace = activeWorkspace
        if let opener, !opener.isPinned, let index = workspace.tabs.firstIndex(where: { $0 === opener }) {
            workspace.tabs.insert(tab, at: index + 1)
        } else {
            workspace.tabs.append(tab)
        }
        setNeedsSave()
    }

    func webViewDidFocus(_ tab: BrowserTab) {
        let workspace = activeWorkspace
        guard workspace.selectedTabID != tab.id, workspace.split?.tabIDs.contains(tab.id) == true else { return }
        workspace.selectedTabID = tab.id
        tab.lastActive = Date()
    }

    private func focusWebView(of tab: BrowserTab) {
        Task { [weak tab] in
            // Give SwiftUI a moment to put the web view in the window.
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard let tab, self.commandBar == nil, let webView = tab.webView, let window = webView.window else { return }
            window.makeFirstResponder(webView)
        }
    }

    private func mostRecentTab(in workspace: Workspace, excluding excluded: BrowserTab? = nil) -> BrowserTab? {
        let candidates = workspace.tabs.isEmpty ? essentials : workspace.tabs
        return candidates.filter { $0 !== excluded }.max { $0.lastActive < $1.lastActive }
    }

    func selectAdjacentTab(_ offset: Int) {
        let tabs = visibleTabs
        guard !tabs.isEmpty else { return }
        let index = currentTab.flatMap { current in tabs.firstIndex { $0 === current } } ?? (offset > 0 ? -1 : 0)
        select(tabs[((index + offset) % tabs.count + tabs.count) % tabs.count])
    }

    /// ⌘1…⌘8 pick a tab by position; ⌘9 (index -1) picks the last one.
    func selectTab(at index: Int) {
        let tabs = visibleTabs
        if index < 0, let last = tabs.last {
            select(last)
        } else if tabs.indices.contains(index) {
            select(tabs[index])
        }
    }

    // MARK: Closing

    func close(_ tab: BrowserTab) {
        if let glance, glance.tab === tab {
            closeGlance()
            return
        }
        if let index = essentials.firstIndex(where: { $0 === tab }) {
            remember(tab, workspace: nil, index: index, essential: true)
            essentials.remove(at: index)
        } else if let owner = workspace(containing: tab), let index = owner.tabs.firstIndex(where: { $0 === tab }) {
            remember(tab, workspace: owner, index: index, essential: false)
            owner.tabs.remove(at: index)
        } else {
            return
        }
        if glance?.parentID == tab.id { closeGlance() }
        tab.unload()
        reconcile()
        if let current = currentTab { select(current) }
    }

    /// ⌘W. Pinned tabs and Essentials aren't closed: like Zen, they go back to
    /// their pinned page, unload, and selection moves on.
    func closeCurrentTab() {
        if glance != nil {
            closeGlance()
            return
        }
        guard let tab = currentTab else { return }
        if tab.isPinned || isEssential(tab) {
            resetAndUnload(tab)
        } else {
            close(tab)
        }
    }

    /// The × on a sidebar row.
    func closeFromSidebar(_ tab: BrowserTab) {
        if tab.isPinned || isEssential(tab) {
            resetAndUnload(tab)
        } else {
            close(tab)
        }
    }

    func resetAndUnload(_ tab: BrowserTab) {
        let workspace = activeWorkspace
        if workspace.selectedTabID == tab.id {
            workspace.selectedTabID = mostRecentTab(in: workspace, excluding: tab)?.id
        }
        tab.resetToPinnedURL(unload: true)
        if tab.pinnedURL == nil { tab.unload() }
        if let current = currentTab { select(current) }
        setNeedsSave()
    }

    func unload(_ tab: BrowserTab) {
        if tab === currentTab {
            let workspace = activeWorkspace
            let next = workspace.tabs.filter { $0 !== tab && $0.isLoaded }.max { $0.lastActive < $1.lastActive }
            workspace.selectedTabID = next?.id
            if let next { select(next) }
        }
        tab.unload()
    }

    /// The "Clear" button: closes every unpinned tab in the active workspace.
    func clearRegularTabs() {
        let workspace = activeWorkspace
        let closing = workspace.regularTabs
        guard !closing.isEmpty else { return }
        for tab in closing {
            if let index = workspace.tabs.firstIndex(where: { $0 === tab }) {
                remember(tab, workspace: workspace, index: index, essential: false)
            }
        }
        workspace.tabs.removeAll { !$0.isPinned }
        closing.forEach { $0.unload() }
        reconcile()
        if let current = currentTab { select(current) }
    }

    func reopenClosedTab() {
        guard let record = closedTabs.popLast() else { return }
        let tab = BrowserTab(
            url: record.url,
            title: record.title,
            isPinned: record.isPinned,
            pinnedURL: record.pinnedURL,
            interactionState: record.interactionState
        )
        tab.store = self
        if record.wasEssential {
            essentials.insert(tab, at: min(record.index, essentials.count))
        } else {
            let workspace = workspaces.first { $0.id == record.workspaceID } ?? activeWorkspace
            workspace.tabs.insert(tab, at: min(record.index, workspace.tabs.count))
            workspace.normalizeOrder()
            if workspace.id != activeWorkspaceID { activeWorkspaceID = workspace.id }
        }
        select(tab)
    }

    private func remember(_ tab: BrowserTab, workspace: Workspace?, index: Int, essential: Bool) {
        guard tab.url != nil else { return }
        closedTabs.append(ClosedTabRecord(
            url: tab.url,
            title: tab.title,
            workspaceID: workspace?.id,
            index: index,
            isPinned: tab.isPinned,
            pinnedURL: tab.pinnedURL,
            wasEssential: essential,
            interactionState: tab.interactionStateForSaving
        ))
        if closedTabs.count > 50 { closedTabs.removeFirst(closedTabs.count - 50) }
    }

    /// Repairs selections and split groups after tabs moved or went away.
    private func reconcile() {
        let essentialIDs = Set(essentials.map { $0.id })
        for workspace in workspaces {
            let reachable = Set(workspace.tabs.map { $0.id }).union(essentialIDs)
            if let selected = workspace.selectedTabID, !reachable.contains(selected) {
                workspace.selectedTabID = mostRecentTab(in: workspace)?.id
            }
            if var split = workspace.split {
                let kept = split.tabIDs.filter { reachable.contains($0) }
                if kept.count < 2 {
                    workspace.split = nil
                } else if kept != split.tabIDs {
                    split.tabIDs = kept
                    split.fractions = SplitGroup.equal(kept.count)
                    workspace.split = split
                }
            }
        }
        setNeedsSave()
    }

    // MARK: Pinning & Essentials

    func togglePin(_ tab: BrowserTab) {
        if isEssential(tab) {
            removeFromEssentials(tab)
            return
        }
        guard let owner = workspace(containing: tab) else { return }
        tab.isPinned.toggle()
        tab.pinnedURL = tab.isPinned ? tab.url : nil
        owner.normalizeOrder()
        setNeedsSave()
    }

    func addToEssentials(_ tab: BrowserTab) {
        guard !isEssential(tab), let owner = workspace(containing: tab) else { return }
        owner.tabs.removeAll { $0 === tab }
        tab.isPinned = true
        if tab.pinnedURL == nil { tab.pinnedURL = tab.url }
        essentials.append(tab)
        reconcile()
    }

    func removeFromEssentials(_ tab: BrowserTab) {
        guard let index = essentials.firstIndex(where: { $0 === tab }) else { return }
        essentials.remove(at: index)
        tab.isPinned = false
        tab.pinnedURL = nil
        let workspace = activeWorkspace
        workspace.tabs.append(tab)
        workspace.normalizeOrder()
        reconcile()
    }

    func duplicate(_ tab: BrowserTab) {
        guard let url = tab.url else { return }
        openTab(url: url, relatedTo: tab)
    }

    func copyLink(of tab: BrowserTab?) {
        guard let url = tab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func move(_ tab: BrowserTab, to target: Workspace) {
        guard let source = workspace(containing: tab), source !== target else { return }
        let wasCurrent = tab === currentTab
        source.tabs.removeAll { $0 === tab }
        target.tabs.append(tab)
        target.normalizeOrder()
        reconcile()
        if wasCurrent, let current = currentTab { select(current) }
    }

    // MARK: Drag & drop

    /// Sidebar drops carry a tab's UUID; a dropped web link opens as a new tab.
    func handleDrop(_ providers: [NSItemProvider], target: TabDropTarget) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = (object as? NSString).map({ String($0) }) else { return }
            Task { @MainActor in self.performDrop(string, target: target) }
        }
        return true
    }

    private func performDrop(_ payload: String, target: TabDropTarget) {
        if let id = UUID(uuidString: payload), let tab = tab(withID: id) {
            moveTab(tab, to: target)
        } else if let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme == "http" || url.scheme == "https" {
            let tab = openTab(url: url)
            moveTab(tab, to: target)
        }
    }

    private func moveTab(_ tab: BrowserTab, to target: TabDropTarget) {
        switch target {
        case .workspace(let workspace):
            if isEssential(tab) { return }
            move(tab, to: workspace)
            return

        case .essentials(let before):
            guard before !== tab else { return }
            detach(tab)
            tab.isPinned = true
            if tab.pinnedURL == nil { tab.pinnedURL = tab.url }
            let index = before.flatMap { anchor in essentials.firstIndex { $0 === anchor } } ?? essentials.count
            essentials.insert(tab, at: index)

        case .pinned(let before), .regular(let before):
            guard before !== tab else { return }
            var pinned = false
            if case .pinned = target { pinned = true }
            detach(tab)
            let workspace = activeWorkspace
            tab.isPinned = pinned
            tab.pinnedURL = pinned ? (tab.pinnedURL ?? tab.url) : nil
            if let before, let index = workspace.tabs.firstIndex(where: { $0 === before }) {
                workspace.tabs.insert(tab, at: index)
            } else if pinned {
                let index = workspace.tabs.lastIndex(where: { $0.isPinned }).map { $0 + 1 } ?? 0
                workspace.tabs.insert(tab, at: index)
            } else {
                workspace.tabs.append(tab)
            }
            workspace.normalizeOrder()
        }
        reconcile()
    }

    private func detach(_ tab: BrowserTab) {
        if isEssential(tab) { essentials.removeAll { $0 === tab } }
        for workspace in workspaces where workspace.contains(tab) {
            workspace.tabs.removeAll { $0 === tab }
        }
    }

    // MARK: Workspaces

    func createWorkspace() {
        let count = workspaces.count
        let workspace = Workspace(
            name: "Workspace \(count + 1)",
            icon: Workspace.suggestedIcons[count % Workspace.suggestedIcons.count],
            theme: WorkspaceTheme.presets[count % WorkspaceTheme.presets.count]
        )
        workspaces.append(workspace)
        switchTo(workspace)
        editingWorkspace = workspace
    }

    func switchTo(_ workspace: Workspace) {
        guard workspace.id != activeWorkspaceID else { return }
        if glance != nil { closeGlance() }
        activeWorkspaceID = workspace.id
        if let current = currentTab { select(current) }
        setNeedsSave()
    }

    func switchWorkspace(by offset: Int) {
        guard workspaces.count > 1, let index = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }
        switchTo(workspaces[((index + offset) % workspaces.count + workspaces.count) % workspaces.count])
    }

    func deleteWorkspace(_ workspace: Workspace) {
        guard workspaces.count > 1 else {
            NSSound.beep()
            return
        }
        if !workspace.tabs.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Delete “\(workspace.name)”?"
            alert.informativeText = workspace.tabs.count == 1
                ? "Its tab will be closed."
                : "Its \(workspace.tabs.count) tabs will be closed."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        workspace.tabs.forEach { $0.unload() }
        let wasActive = workspace.id == activeWorkspaceID
        workspaces.removeAll { $0 === workspace }
        if wasActive {
            activeWorkspaceID = workspaces[0].id
            if let current = currentTab { select(current) }
        }
        setNeedsSave()
    }

    // MARK: Split view

    /// ⌃⌘\: splits the current tab with the one used before it, or unsplits.
    func toggleSplitView() {
        let workspace = activeWorkspace
        guard let current = currentTab else { return }
        if let split = workspace.split, split.tabIDs.contains(current.id) {
            workspace.split = nil
            setNeedsSave()
            return
        }
        let partner = visibleTabs.filter { $0 !== current }.max { $0.lastActive < $1.lastActive }
        if let partner { split(current, with: partner) }
    }

    /// From a tab's context menu: puts `tab` next to the current tab.
    func splitWithCurrent(_ tab: BrowserTab) {
        let workspace = activeWorkspace
        guard let current = currentTab, current !== tab else { return }
        if var split = workspace.split, split.tabIDs.contains(current.id) {
            guard !split.tabIDs.contains(tab.id), split.tabIDs.count < SplitGroup.maxPanes else { return }
            split.tabIDs.append(tab.id)
            split.fractions = SplitGroup.equal(split.tabIDs.count)
            workspace.split = split
            tab.ensureWebView()
            setNeedsSave()
        } else {
            split(current, with: tab)
        }
    }

    func split(_ first: BrowserTab, with second: BrowserTab, focusing focused: BrowserTab? = nil) {
        activeWorkspace.split = SplitGroup(tabIDs: [first.id, second.id])
        second.ensureWebView()
        first.ensureWebView()
        select(focused ?? first)
    }

    func removeFromSplit(_ tab: BrowserTab) {
        let workspace = activeWorkspace
        guard var split = workspace.split, let index = split.tabIDs.firstIndex(of: tab.id) else { return }
        split.tabIDs.remove(at: index)
        split.fractions = SplitGroup.equal(split.tabIDs.count)
        workspace.split = split.tabIDs.count >= 2 ? split : nil
        setNeedsSave()
    }

    func rotateSplit() {
        let workspace = activeWorkspace
        guard var split = workspace.split else { return }
        split.axis = split.axis == .horizontal ? .vertical : .horizontal
        workspace.split = split
        setNeedsSave()
    }

    func updateSplitFractions(_ fractions: [Double]) {
        let workspace = activeWorkspace
        guard var split = workspace.split, split.tabIDs.count == fractions.count else { return }
        split.fractions = fractions
        workspace.split = split
        setNeedsSave()
    }

    // MARK: Glance

    /// ⌥-click: shows the link in a floating preview over the current page.
    func openGlance(url: URL, from opener: BrowserTab?) {
        if let glance {
            glance.tab.load(url)
            return
        }
        let tab = BrowserTab(url: url)
        tab.store = self
        tab.ensureWebView()
        glance = GlanceState(tab: tab, parentID: opener?.id)
        focusWebView(of: tab)
    }

    func closeGlance() {
        guard let glance else { return }
        self.glance = nil
        glance.tab.unload()
        if let current = currentTab { focusWebView(of: current) }
    }

    /// Turns the preview into a regular tab.
    func expandGlance() {
        guard let glance else { return }
        self.glance = nil
        let parent = glance.parentID.flatMap { tab(withID: $0) }
        insert(glance.tab, after: parent)
        select(glance.tab)
    }

    func expandGlanceIntoSplit() {
        guard let glance else { return }
        let parent = glance.parentID.flatMap { tab(withID: $0) } ?? currentTab
        expandGlance()
        if let parent, parent !== glance.tab {
            split(parent, with: glance.tab, focusing: glance.tab)
        }
    }

    // MARK: Command bar

    func presentCommandBar(_ mode: CommandBarMode) {
        if mode == .navigate, let tab = currentTab {
            commandBar = CommandBarRequest(mode: .navigate, initialText: tab.url?.absoluteString ?? "")
        } else {
            commandBar = CommandBarRequest(mode: .newTab, initialText: "")
        }
    }

    func dismissCommandBar() {
        commandBar = nil
        if let current = currentTab { focusWebView(of: current) }
    }

    func perform(_ suggestion: Suggestion, mode: CommandBarMode) {
        commandBar = nil
        switch suggestion.action {
        case .switchTo(let tab):
            select(tab)
        case .open(let url):
            if mode == .navigate, let tab = currentTab {
                tab.load(url)
                focusWebView(of: tab)
            } else {
                openTab(url: url)
            }
        }
    }

    func suggestions(for text: String, mode: CommandBarMode, remote: [String]) -> [Suggestion] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = mode == .navigate ? currentTab : nil

        if query.isEmpty {
            return allTabs
                .filter { $0 !== current && $0.url != nil }
                .sorted { $0.lastActive > $1.lastActive }
                .prefix(6)
                .map(tabSuggestion)
        }
        // In ⌘L the field starts out holding the current URL; offer just that.
        if let current, query == current.url?.absoluteString, let url = current.url {
            return [Suggestion(id: "open:\(url)", icon: "arrow.clockwise", title: url.absoluteString,
                               subtitle: "Reload", action: .open(url))]
        }

        let engine = Preferences.searchEngine
        var results: [Suggestion] = []
        var seen = Set<String>()
        func add(_ suggestion: Suggestion, url: URL? = nil) {
            guard !seen.contains(suggestion.id) else { return }
            if let url {
                guard !seen.contains(url.absoluteString) else { return }
                seen.insert(url.absoluteString)
            }
            seen.insert(suggestion.id)
            results.append(suggestion)
        }

        if let url = URLResolver.directURL(query) {
            add(Suggestion(id: "open:\(url)", icon: "arrow.up.right.square", title: url.absoluteString,
                           subtitle: "Open address", action: .open(url)), url: url)
        } else if let url = engine.searchURL(for: query) {
            add(Suggestion(id: "search:\(query)", icon: "magnifyingglass", title: query,
                           subtitle: "Search with \(engine.name)", action: .open(url)))
        }

        let lower = query.lowercased()
        let matchingTabs = allTabs.filter { tab in
            tab !== current && (tab.displayTitle.lowercased().contains(lower)
                || (tab.url?.absoluteString.lowercased().contains(lower) ?? false))
        }
        for tab in matchingTabs.prefix(4) { add(tabSuggestion(tab), url: tab.url) }

        for entry in history.search(query, limit: remote.isEmpty ? 6 : 4) {
            add(Suggestion(id: "history:\(entry.url)", icon: "clock",
                           favicon: FaviconCache.shared.cached(forHost: entry.url.host),
                           title: entry.title.isEmpty ? entry.url.absoluteString : entry.title,
                           subtitle: entry.url.absoluteString, action: .open(entry.url)),
                url: entry.url)
        }

        for phrase in remote.prefix(5) where phrase.lowercased() != lower {
            if let url = engine.searchURL(for: phrase) {
                add(Suggestion(id: "search:\(phrase)", icon: "magnifyingglass", title: phrase,
                               subtitle: nil, action: .open(url)))
            }
        }
        return Array(results.prefix(10))
    }

    private func tabSuggestion(_ tab: BrowserTab) -> Suggestion {
        Suggestion(
            id: "tab:\(tab.id)",
            icon: "square.on.square",
            favicon: tab.favicon,
            title: tab.displayTitle,
            subtitle: tab.url?.absoluteString,
            badge: "Switch to Tab",
            action: .switchTo(tab)
        )
    }

    // MARK: Find in page

    func showFindBar() {
        isFindBarVisible = true
        findFocusRequest += 1
    }

    func hideFindBar() {
        isFindBarVisible = false
        findHasMatch = true
        if let current = currentTab { focusWebView(of: current) }
    }

    func findNext(backwards: Bool = false) {
        guard !findQuery.isEmpty, let webView = currentTab?.webView else {
            findHasMatch = true
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(findQuery, configuration: configuration) { [weak self] result in
            let found = result.matchFound
            Task { @MainActor [weak self] in self?.findHasMatch = found }
        }
    }

    // MARK: Compact mode

    func toggleCompactMode() {
        withAnimation(.easeInOut(duration: 0.2)) { isCompact.toggle() }
    }

    func setCompactSidebarRevealed(_ revealed: Bool) {
        guard isCompact, isCompactSidebarRevealed != revealed else { return }
        withAnimation(.easeOut(duration: 0.18)) { isCompactSidebarRevealed = revealed }
    }

    // MARK: Window

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingMode = .disallowed
        updateWindowChrome()
        installKeyMonitor()
    }

    private func updateWindowChrome() {
        guard let window else { return }
        let hidden = isCompact && !isCompactSidebarRevealed
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    /// Shortcuts that must win over the web page and AppKit's defaults.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handleKeyDown(event) }
            return handled ? nil : event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased()

        switch (event.keyCode, flags) {
        case (53, []): // Esc
            if commandBar != nil { return false }
            if glance != nil {
                closeGlance()
                return true
            }
            if isFindBarVisible {
                hideFindBar()
                return true
            }
            return false
        case (48, [.control]): // ⌃⇥
            selectAdjacentTab(1)
            return true
        case (48, [.control, .shift]):
            selectAdjacentTab(-1)
            return true
        default:
            if key == "w" && flags == [.command] {
                closeCurrentTab()
                return true
            }
            return false
        }
    }

    // MARK: Background unloading

    private func startUnloadTimer() {
        unloadTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.unloadIdleTabs() }
        }
    }

    private func unloadIdleTabs() {
        let minutes = Preferences.unloadAfterMinutes
        guard minutes > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(minutes) * 60)
        var keep = Set(workspaces.compactMap { $0.selectedTabID })
        workspaces.compactMap { $0.split }.forEach { keep.formUnion($0.tabIDs) }
        for tab in allTabs where tab.isLoaded && !keep.contains(tab.id) && tab.lastActive < cutoff {
            tab.unload()
        }
    }

    // MARK: Persistence

    func setNeedsSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        SessionStore.save(snapshot())
        history.saveNow()
    }

    private func snapshot() -> SessionSnapshot {
        func tabSnapshot(_ tab: BrowserTab) -> TabSnapshot {
            TabSnapshot(id: tab.id, url: tab.url, title: tab.title, isPinned: tab.isPinned,
                        pinnedURL: tab.pinnedURL, interactionState: tab.interactionStateForSaving)
        }
        return SessionSnapshot(
            version: 1,
            workspaces: workspaces.map { workspace in
                WorkspaceSnapshot(
                    id: workspace.id,
                    name: workspace.name,
                    icon: workspace.icon,
                    theme: workspace.theme,
                    tabs: workspace.tabs.filter { $0.url != nil }.map(tabSnapshot),
                    selectedTabID: workspace.selectedTabID,
                    split: workspace.split
                )
            },
            essentials: essentials.filter { $0.url != nil }.map(tabSnapshot),
            activeWorkspaceID: activeWorkspaceID
        )
    }

    private func restore(_ snapshot: SessionSnapshot) {
        func makeTab(_ saved: TabSnapshot) -> BrowserTab {
            let tab = BrowserTab(id: saved.id, url: saved.url, title: saved.title, isPinned: saved.isPinned,
                                 pinnedURL: saved.pinnedURL, interactionState: saved.interactionState,
                                 lastActive: .distantPast)
            tab.store = self
            return tab
        }
        essentials = snapshot.essentials.map(makeTab)
        workspaces = snapshot.workspaces.map { saved in
            let workspace = Workspace(id: saved.id, name: saved.name, icon: saved.icon, theme: saved.theme,
                                      tabs: saved.tabs.map(makeTab), selectedTabID: saved.selectedTabID,
                                      split: saved.split)
            workspace.normalizeOrder()
            return workspace
        }
        if let active = workspaces.first(where: { $0.id == snapshot.activeWorkspaceID }) {
            activeWorkspaceID = active.id
        } else if let first = workspaces.first {
            activeWorkspaceID = first.id
        }
        if !workspaces.isEmpty { reconcile() }
        currentTab?.lastActive = Date()
    }
}
