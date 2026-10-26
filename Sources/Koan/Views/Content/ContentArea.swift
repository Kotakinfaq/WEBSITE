import SwiftUI

/// The page area: one tab, a split view, or the empty state.
struct ContentArea: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var workspace: Workspace

    var body: some View {
        Group {
            if let split = workspace.split,
               let selected = workspace.selectedTabID,
               split.tabIDs.contains(selected) {
                SplitContainer(workspace: workspace, split: split)
            } else if let tab = store.currentTab {
                WebPane(tab: tab)
            } else {
                EmptyState()
            }
        }
    }
}

struct WebPane: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var tab: BrowserTab
    var isFocused = true
    var showsFocusRing = false
    var accent: Color = .accentColor

    var body: some View {
        let highlighted = showsFocusRing && isFocused
        ZStack(alignment: .top) {
            WebViewHost(tab: tab, isLoaded: tab.isLoaded)
            if tab.isLoading && tab.progress < 1 {
                ProgressLine(progress: tab.progress, color: accent)
            }
            if let error = tab.loadError {
                LoadErrorView(message: error, url: tab.url) { tab.reload() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.16), radius: 5, y: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(highlighted ? accent : Color.black.opacity(0.07), lineWidth: highlighted ? 2 : 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if isFocused && store.isFindBarVisible && store.glance?.tab !== tab {
                FindBar().padding(10)
            }
        }
    }
}

private struct LoadErrorView: View {
    let message: String
    let url: URL?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Koan can’t open this page")
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let url {
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Try Again", action: retry)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct EmptyState: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        VStack(spacing: 14) {
            Text("Koan")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                shortcut("⌘T", "New tab")
                shortcut("⌥-click", "Peek at a link with Glance")
                shortcut("⌃⌘\\", "Split view")
                shortcut("⌃⌘S", "Compact mode")
            }
            Button("New Tab") { store.presentCommandBar(.newTab) }
                .controlSize(.large)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
        )
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .frame(width: 70, alignment: .trailing)
            Text(label)
                .font(.system(size: 12))
                .frame(width: 190, alignment: .leading)
        }
        .foregroundStyle(.secondary)
    }
}

/// Two to four panes with draggable dividers.
private struct SplitContainer: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var workspace: Workspace
    let split: SplitGroup
    @State private var dragBase: [Double]?
    @State private var liveFractions: [Double]?

    private let gap: CGFloat = 8

    var body: some View {
        let tabs = split.tabIDs.compactMap { store.tab(withID: $0) }
        let fractions = SplitGroup.normalized(liveFractions ?? split.fractions, count: tabs.count)
        let horizontal = split.axis == .horizontal
        GeometryReader { geometry in
            let total = horizontal ? geometry.size.width : geometry.size.height
            let length = max(total - gap * CGFloat(max(tabs.count - 1, 0)), 1)
            let layout = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    WebPane(
                        tab: tab,
                        isFocused: tab.id == workspace.selectedTabID,
                        showsFocusRing: true,
                        accent: workspace.theme.primaryColor
                    )
                    .frame(
                        width: horizontal ? length * fractions[index] : nil,
                        height: horizontal ? nil : length * fractions[index]
                    )

                    if index < tabs.count - 1 {
                        SplitDivider(horizontal: horizontal)
                            .frame(width: horizontal ? gap : nil, height: horizontal ? nil : gap)
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { value in
                                        let base = dragBase ?? fractions
                                        if dragBase == nil { dragBase = base }
                                        let moved = horizontal ? value.translation.width : value.translation.height
                                        liveFractions = SplitGroup.adjust(base, at: index, delta: Double(moved / length))
                                    }
                                    .onEnded { _ in
                                        if let liveFractions { store.updateSplitFractions(liveFractions) }
                                        dragBase = nil
                                        liveFractions = nil
                                    }
                            )
                    }
                }
            }
        }
    }
}

private struct SplitDivider: View {
    let horizontal: Bool
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color.primary.opacity(hovering ? 0.35 : 0))
                .frame(width: horizontal ? 3 : 36, height: horizontal ? 36 : 3)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .resizeCursor(horizontal ? .resizeLeftRight : .resizeUpDown)
    }
}

struct FindBar: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            CommandTextField(
                text: $store.findQuery,
                placeholder: "Find in page",
                fontSize: 13,
                focusRequest: store.findFocusRequest,
                onSubmit: { flags in store.findNext(backwards: flags.contains(.shift)) },
                onMove: { direction in store.findNext(backwards: direction < 0) },
                onCancel: { store.hideFindBar() }
            )
            .frame(width: 180, height: 20)
            if !store.findQuery.isEmpty && !store.findHasMatch {
                Text("Not found")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            IconButton(systemName: "chevron.up", help: "Previous (⇧⌘G)", size: 11) { store.findNext(backwards: true) }
                .frame(width: 24)
            IconButton(systemName: "chevron.down", help: "Next (⌘G)", size: 11) { store.findNext() }
                .frame(width: 24)
            IconButton(systemName: "xmark", help: "Done (Esc)", size: 11) { store.hideFindBar() }
                .frame(width: 24)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .onChange(of: store.findQuery) { _ in store.findNext() }
    }
}
