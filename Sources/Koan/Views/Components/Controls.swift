import AppKit
import SwiftUI

/// A small borderless toolbar button with a hover highlight.
struct IconButton: View {
    let systemName: String
    var help: String = ""
    var size: CGFloat = 13
    var isEnabled = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering && isEnabled ? 0.09 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary.opacity(isEnabled ? 0.75 : 0.3))
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct FaviconView: View {
    @ObservedObject var tab: BrowserTab
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if tab.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(size / 20)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Fill for the selected tab row / Essential tile.
struct SelectionFill: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.72))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 1.5, y: 1)
    }
}

/// A thin determinate progress line.
struct ProgressLine: View {
    let progress: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(color)
                .frame(width: geometry.size.width * min(max(progress, 0.05), 1))
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .frame(height: 2)
    }
}

/// Pushes a resize cursor while hovered.
struct ResizeCursor: ViewModifier {
    let cursor: NSCursor
    @State private var pushed = false

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside, !pushed {
                cursor.push()
                pushed = true
            } else if !inside, pushed {
                NSCursor.pop()
                pushed = false
            }
        }
    }
}

extension View {
    func resizeCursor(_ cursor: NSCursor) -> some View {
        modifier(ResizeCursor(cursor: cursor))
    }
}
