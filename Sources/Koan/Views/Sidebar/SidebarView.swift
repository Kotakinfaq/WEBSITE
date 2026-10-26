import SwiftUI
import UniformTypeIdentifiers

/// Zen-style vertical sidebar: toolbar, address, Essentials, the workspace's
/// pinned and regular tabs, and the workspace switcher.
struct SidebarView: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 8) {
            SidebarToolbar()
            if let tab = store.currentTab {
                AddressPill(tab: tab, accent: workspace.theme.primaryColor)
            } else {
                EmptyAddressPill()
            }
            EssentialsGrid(selectedID: workspace.selectedTabID, accent: workspace.theme.primaryColor)
            WorkspaceTabList(workspace: workspace)
                .id(workspace.id)
                .transition(.opacity.combined(with: .offset(x: 12)))
            SidebarFooter(activeID: workspace.id)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: workspace.id)
    }
}

private struct SidebarToolbar: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        HStack(spacing: 0) {
            // Room for the traffic lights.
            Spacer().frame(width: 70)
            if let tab = store.currentTab {
                NavigationButtons(tab: tab)
            } else {
                IconButton(systemName: "chevron.left", isEnabled: false) {}
                IconButton(systemName: "chevron.right", isEnabled: false) {}
                IconButton(systemName: "arrow.clockwise", isEnabled: false) {}
            }
            Spacer(minLength: 0)
            IconButton(systemName: "sidebar.left", help: store.isCompact ? "Exit Compact Mode (⌃⌘S)" : "Compact Mode (⌃⌘S)") {
                store.toggleCompactMode()
            }
        }
        .frame(height: 30)
        .padding(.top, 6)
    }
}

private struct NavigationButtons: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        IconButton(systemName: "chevron.left", help: "Back (⌘[)", isEnabled: tab.canGoBack) { tab.goBack() }
        IconButton(systemName: "chevron.right", help: "Forward (⌘])", isEnabled: tab.canGoForward) { tab.goForward() }
        if tab.isLoading {
            IconButton(systemName: "xmark", help: "Stop (⌘.)") { tab.stopLoading() }
        } else {
            IconButton(systemName: "arrow.clockwise", help: "Reload (⌘R)") { tab.reload() }
        }
    }
}

private struct AddressPill: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var tab: BrowserTab
    let accent: Color
    @State private var hovering = false

    var body: some View {
        Button {
            store.presentCommandBar(.navigate)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: tab.isSecure ? "lock.fill" : "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(URLResolver.displayHost(tab.url) ?? "Search or enter address")
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .foregroundStyle(tab.url == nil ? Color.secondary : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.1 : 0.065))
            )
            .overlay(alignment: .bottom) {
                if tab.isLoading {
                    ProgressLine(progress: tab.progress, color: accent)
                        .padding(.horizontal, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.url?.absoluteString ?? "")
    }
}

private struct EmptyAddressPill: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        Button {
            store.presentCommandBar(.newTab)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                Text("Search or enter address").font(.system(size: 12.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.065)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Essentials

private struct EssentialsGrid: View {
    @EnvironmentObject private var store: BrowserStore
    let selectedID: UUID?
    let accent: Color

    var body: some View {
        if !store.essentials.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 6) {
                ForEach(store.essentials) { tab in
                    EssentialTile(tab: tab, isSelected: tab.id == selectedID, accent: accent)
                }
            }
            .padding(.top, 2)
        }
    }
}

private struct EssentialTile: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let accent: Color
    @State private var hovering = false

    var body: some View {
        FaviconView(tab: tab, size: 20)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                if isSelected {
                    SelectionFill(cornerRadius: 11)
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.11 : 0.06))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? accent : .clear, lineWidth: 1.5)
            )
            .opacity(tab.isLoaded || isSelected ? 1 : 0.6)
            .contentShape(Rectangle())
            .onTapGesture { store.select(tab) }
            .onHover { hovering = $0 }
            .help(tab.displayTitle)
            .contextMenu { TabContextMenu(store: store, tab: tab) }
            .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                store.handleDrop(providers, target: .essentials(before: tab))
            }
    }
}

// MARK: - Tabs

private struct WorkspaceTabList: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var workspace: Workspace

    var body: some View {
        let pinned = workspace.pinnedTabs
        let regular = workspace.regularTabs
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
                WorkspaceHeader(workspace: workspace)
                    .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                        store.handleDrop(providers, target: .pinned(before: pinned.first))
                    }

                ForEach(pinned) { tab in
                    row(for: tab, pinnedSection: true)
                }

                TabSeparator(showsClear: !regular.isEmpty) { store.clearRegularTabs() }
                    .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                        store.handleDrop(providers, target: .regular(before: regular.first))
                    }

                NewTabRow()
                    .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                        store.handleDrop(providers, target: .regular(before: regular.first))
                    }

                ForEach(regular) { tab in
                    row(for: tab, pinnedSection: false)
                }

                // Dropping below the last tab moves it to the end.
                Color.clear
                    .frame(height: 40)
                    .contentShape(Rectangle())
                    .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                        store.handleDrop(providers, target: .regular(before: nil))
                    }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity)
    }

    private func row(for tab: BrowserTab, pinnedSection: Bool) -> some View {
        TabRow(
            tab: tab,
            isSelected: workspace.selectedTabID == tab.id,
            isInSplit: workspace.split?.tabIDs.contains(tab.id) ?? false
        )
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            store.handleDrop(providers, target: pinnedSection ? .pinned(before: tab) : .regular(before: tab))
        }
    }
}

private struct WorkspaceHeader: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var workspace: Workspace

    var body: some View {
        HStack(spacing: 8) {
            Text(workspace.displayIcon).font(.system(size: 14))
            Text(workspace.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                WorkspaceMenuItems(store: store, workspace: workspace)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(0.6)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.editingWorkspace = workspace }
        .contextMenu { WorkspaceMenuItems(store: store, workspace: workspace) }
    }
}

struct WorkspaceMenuItems: View {
    let store: BrowserStore
    let workspace: Workspace

    var body: some View {
        Button("Edit Workspace…") { store.editingWorkspace = workspace }
        Button("New Workspace") { store.createWorkspace() }
        Divider()
        Button("Delete Workspace") { store.deleteWorkspace(workspace) }
            .disabled(store.workspaces.count < 2)
    }
}

private struct TabSeparator: View {
    let showsClear: Bool
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
            if showsClear {
                Button(action: clear) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                        Text("Clear")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close all unpinned tabs")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

private struct NewTabRow: View {
    @EnvironmentObject private var store: BrowserStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16)
            Text("New Tab").font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { store.presentCommandBar(.newTab) }
        .onHover { hovering = $0 }
    }
}

struct TabRow: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let isInSplit: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(tab: tab, size: 16)
            Text(tab.displayTitle)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isInSplit {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help("In split view")
            }
            if tab.isPinned && tab.hasNavigatedAwayFromPinnedURL && hovering {
                IconButton(systemName: "arrow.uturn.backward", help: "Back to pinned page", size: 10) {
                    tab.resetToPinnedURL(unload: false)
                }
                .frame(width: 22)
            }
            if hovering || (isSelected && !tab.isPinned) {
                IconButton(systemName: tab.isPinned ? "minus" : "xmark", help: tab.isPinned ? "Unload" : "Close Tab", size: 10) {
                    store.closeFromSidebar(tab)
                }
                .frame(width: 22)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background {
            if isSelected {
                SelectionFill()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
            }
        }
        .opacity(tab.isLoaded || isSelected ? 1 : 0.62)
        .contentShape(Rectangle())
        .onTapGesture { store.select(tab) }
        .onHover { hovering = $0 }
        .help(tab.url?.absoluteString ?? tab.displayTitle)
        .contextMenu { TabContextMenu(store: store, tab: tab) }
        .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
    }
}

struct TabContextMenu: View {
    let store: BrowserStore
    let tab: BrowserTab

    var body: some View {
        let essential = store.isEssential(tab)
        let owner = store.workspace(containing: tab)

        if tab !== store.currentTab {
            Button(store.isInActiveSplit(store.currentTab ?? tab) ? "Add to Split View" : "Split with Current Tab") {
                store.splitWithCurrent(tab)
            }
        }
        if store.isInActiveSplit(tab) {
            Button("Remove from Split View") { store.removeFromSplit(tab) }
        }
        Divider()
        if essential {
            Button("Remove from Essentials") { store.removeFromEssentials(tab) }
        } else {
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { store.togglePin(tab) }
            Button("Add to Essentials") { store.addToEssentials(tab) }
        }
        if tab.pinnedURL != nil {
            Button("Go Back to Pinned Page") { tab.resetToPinnedURL(unload: false) }
        }
        Button("Duplicate Tab") { store.duplicate(tab) }
        Button("Copy Link") { store.copyLink(of: tab) }
        if !essential, let owner, store.workspaces.count > 1 {
            Menu("Move to Workspace") {
                ForEach(store.workspaces.filter { $0 !== owner }) { workspace in
                    Button("\(workspace.displayIcon)  \(workspace.name)") { store.move(tab, to: workspace) }
                }
            }
        }
        Divider()
        Button("Unload Tab") { store.unload(tab) }
            .disabled(!tab.isLoaded)
        Button("Close Tab") { store.close(tab) }
    }
}

// MARK: - Footer

private struct SidebarFooter: View {
    @EnvironmentObject private var store: BrowserStore
    let activeID: UUID

    var body: some View {
        HStack(spacing: 4) {
            DownloadsButton(downloads: store.downloads)
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(store.workspaces) { workspace in
                        WorkspaceButton(workspace: workspace, isActive: workspace.id == activeID)
                    }
                }
                .frame(minWidth: 0)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity)
            IconButton(systemName: "plus", help: "New Workspace (⌃⌘N)") { store.createWorkspace() }
        }
        .frame(height: 30)
    }
}

private struct WorkspaceButton: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var workspace: Workspace
    let isActive: Bool
    @State private var hovering = false

    var body: some View {
        Text(workspace.displayIcon)
            .font(.system(size: 14))
            .frame(width: 28, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isActive ? 0.13 : (hovering ? 0.07 : 0)))
            )
            .grayscale(isActive ? 0 : 0.6)
            .contentShape(Rectangle())
            .onTapGesture { store.switchTo(workspace) }
            .onHover { hovering = $0 }
            .help(workspace.name)
            .contextMenu { WorkspaceMenuItems(store: store, workspace: workspace) }
            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                store.handleDrop(providers, target: .workspace(workspace))
            }
    }
}

private struct DownloadsButton: View {
    @ObservedObject var downloads: DownloadManager
    @State private var showing = false

    var body: some View {
        IconButton(
            systemName: downloads.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle",
            help: "Downloads"
        ) {
            showing.toggle()
            downloads.hasUnseenActivity = false
        }
        .overlay(alignment: .topTrailing) {
            if downloads.hasUnseenActivity {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6).offset(x: -4, y: 3)
            }
        }
        .popover(isPresented: $showing, arrowEdge: .top) {
            DownloadsList(downloads: downloads)
        }
    }
}
