import SwiftUI

struct BrowserCommands: Commands {
    @ObservedObject var store: BrowserStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { store.presentCommandBar(.newTab) }
                .keyboardShortcut("t")
            Button("Open Location…") { store.presentCommandBar(.navigate) }
                .keyboardShortcut("l")
            Button("Reopen Closed Tab") { store.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("New Workspace") { store.createWorkspace() }
                .keyboardShortcut("n", modifiers: [.command, .control])
            Divider()
            // ⌘W itself is caught by the store's key monitor so it beats the
            // window's Close item; this entry is for the menu.
            Button("Close Tab") { store.closeCurrentTab() }
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find…") { store.showFindBar() }
                .keyboardShortcut("f")
            Button("Find Next") { store.findNext() }
                .keyboardShortcut("g")
            Button("Find Previous") { store.findNext(backwards: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button(store.isCompact ? "Exit Compact Mode" : "Enter Compact Mode") { store.toggleCompactMode() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Button("Toggle Split View") { store.toggleSplitView() }
                .keyboardShortcut("\\", modifiers: [.command, .control])
            Button("Rotate Split View") { store.rotateSplit() }
            Divider()
            Button("Reload Page") { store.currentTab?.reload() }
                .keyboardShortcut("r")
            Button("Reload Ignoring Cache") { store.currentTab?.reloadFromOrigin() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Stop Loading") { store.currentTab?.stopLoading() }
                .keyboardShortcut(".")
            Divider()
            Button("Zoom In") { store.currentTab?.zoomIn() }
                .keyboardShortcut("=")
            Button("Zoom Out") { store.currentTab?.zoomOut() }
                .keyboardShortcut("-")
            Button("Actual Size") { store.currentTab?.resetZoom() }
                .keyboardShortcut("0")
            Divider()
        }

        CommandMenu("History") {
            Button("Back") { store.currentTab?.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { store.currentTab?.goForward() }
                .keyboardShortcut("]")
        }

        CommandMenu("Tabs") {
            Button("Next Tab") { store.selectAdjacentTab(1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Tab") { store.selectAdjacentTab(-1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            Button("Pin or Unpin Tab") { if let tab = store.currentTab { store.togglePin(tab) } }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Add to Essentials") { if let tab = store.currentTab { store.addToEssentials(tab) } }
            Button("Duplicate Tab") { if let tab = store.currentTab { store.duplicate(tab) } }
            Button("Copy Link") { store.copyLink(of: store.currentTab) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Unload Tab") { if let tab = store.currentTab { store.unload(tab) } }
            Divider()
            ForEach(1..<9) { number in
                Button("Tab \(number)") { store.selectTab(at: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
            Button("Last Tab") { store.selectTab(at: -1) }
                .keyboardShortcut("9")
        }

        CommandMenu("Workspaces") {
            Button("Next Workspace") { store.switchWorkspace(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Workspace") { store.switchWorkspace(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, workspace in
                if index < 9 {
                    Button("\(workspace.displayIcon)  \(workspace.name)") { store.switchTo(workspace) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.control, .option])
                } else {
                    Button("\(workspace.displayIcon)  \(workspace.name)") { store.switchTo(workspace) }
                }
            }
            Divider()
            Button("Edit Workspace…") { store.editingWorkspace = store.activeWorkspace }
        }
    }
}
