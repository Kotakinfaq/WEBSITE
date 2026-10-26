import SwiftUI

/// Glance: a floating preview of a link (⌥-click) over the current page.
struct GlanceOverlay: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var tab: BrowserTab

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { store.closeGlance() }

            HStack(alignment: .top, spacing: 10) {
                WebPane(tab: tab)
                    .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
                VStack(spacing: 8) {
                    GlanceButton(systemName: "xmark", help: "Close (Esc)") { store.closeGlance() }
                    GlanceButton(systemName: "arrow.up.left.and.arrow.down.right", help: "Open as Tab") { store.expandGlance() }
                    GlanceButton(systemName: "rectangle.split.2x1", help: "Open in Split View") { store.expandGlanceIntoSplit() }
                    GlanceButton(systemName: "link", help: "Copy Link") { store.copyLink(of: tab) }
                }
            }
            .padding(.vertical, 28)
            .padding(.leading, 56)
            .padding(.trailing, 14)
        }
    }
}

private struct GlanceButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(hovering ? 0.25 : 0.1)))
                .scaleEffect(hovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
    }
}
