import SwiftUI

struct BrowserWindow: View {
    @EnvironmentObject private var store: BrowserStore
    @AppStorage(Preferences.Keys.sidebarWidth) private var sidebarWidth: Double = 250

    var body: some View {
        let workspace = store.activeWorkspace
        ZStack(alignment: .topLeading) {
            WorkspaceBackground(workspace: workspace)

            HStack(spacing: 0) {
                if !store.isCompact {
                    SidebarView(workspace: workspace)
                        .frame(width: sidebarWidth)
                        .overlay(alignment: .trailing) { SidebarResizeHandle(width: $sidebarWidth) }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ContentArea(workspace: workspace)
                    .overlay {
                        if let glance = store.glance {
                            GlanceOverlay(tab: glance.tab)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.86), value: store.glance?.tab.id)
                    .padding(.vertical, store.isCompact ? 6 : 8)
                    .padding(.leading, store.isCompact ? 6 : 0)
                    .padding(.trailing, store.isCompact ? 6 : 8)
            }

            if store.isCompact {
                CompactSidebar(workspace: workspace, width: sidebarWidth)
            }

            if let request = store.commandBar {
                CommandBar(request: request)
                    .id(request.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: store.commandBar?.id)
        .ignoresSafeArea()
        .frame(minWidth: 720, minHeight: 460)
        .background(WindowAccessor { store.attach($0) })
        .sheet(item: $store.editingWorkspace) { workspace in
            WorkspaceEditor(workspace: workspace, store: store)
        }
    }
}

private struct WorkspaceBackground: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        WorkspaceBackdrop(colors: [NSColor(hex: workspace.theme.primary), NSColor(hex: workspace.theme.secondary)])
            .ignoresSafeArea()
    }
}

private struct SidebarResizeHandle: View {
    @Binding var width: Double
    @State private var startWidth: Double?

    var body: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .resizeCursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? width
                        startWidth = start
                        width = min(max(start + value.translation.width, 200), 420)
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}

/// In compact mode the sidebar hides; hovering the window's left edge slides it in.
private struct CompactSidebar: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var workspace: Workspace
    let width: Double
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        hideTask?.cancel()
                        store.setCompactSidebarRevealed(true)
                    }
                }

            if store.isCompactSidebarRevealed {
                SidebarView(workspace: workspace)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background {
                        ZStack {
                            VisualEffectBackground(material: .sidebar, blendingMode: .withinWindow)
                            workspace.theme.gradient.opacity(0.45)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                    .shadow(color: .black.opacity(0.25), radius: 18, x: 4)
                    .padding(6)
                    .onHover { inside in
                        if inside {
                            hideTask?.cancel()
                        } else {
                            scheduleHide()
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, store.commandBar == nil, store.editingWorkspace == nil else { return }
            store.setCompactSidebarRevealed(false)
        }
    }
}
