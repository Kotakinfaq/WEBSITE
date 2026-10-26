import SwiftUI

/// Zen's floating URL bar: search, addresses, open tabs and history in one list.
struct CommandBar: View {
    @EnvironmentObject private var store: BrowserStore
    let request: CommandBarRequest
    @State private var text: String
    @State private var selection = 0
    @State private var remote: [String] = []

    init(request: CommandBarRequest) {
        self.request = request
        _text = State(initialValue: request.initialText)
    }

    var body: some View {
        let items = store.suggestions(for: text, mode: request.mode, remote: remote)
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black.opacity(0.14)
                    .contentShape(Rectangle())
                    .onTapGesture { store.dismissCommandBar() }

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: request.mode == .newTab ? "plus.magnifyingglass" : "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        CommandTextField(
                            text: $text,
                            placeholder: request.mode == .newTab ? "Search or enter address — opens a new tab" : "Search or enter address",
                            fontSize: 18,
                            onSubmit: { _ in activate(items, at: selection) },
                            onMove: { delta in move(delta, count: items.count) },
                            onCancel: { store.dismissCommandBar() }
                        )
                        .frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)

                    if !items.isEmpty {
                        Divider().opacity(0.6)
                        VStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                SuggestionRow(suggestion: item, isSelected: index == selection)
                                    .onTapGesture { activate(items, at: index) }
                                    .onHover { inside in if inside { selection = index } }
                            }
                        }
                        .padding(6)
                    }
                }
                .frame(width: min(640, max(geometry.size.width - 80, 320)))
                .background {
                    ZStack {
                        VisualEffectBackground(material: .popover, blendingMode: .withinWindow)
                        Color(nsColor: .windowBackgroundColor).opacity(0.35)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1))
                )
                .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
                .padding(.top, geometry.size.height * 0.18)
            }
        }
        .onChange(of: text) { _ in selection = 0 }
        .task(id: text) { await loadRemoteSuggestions() }
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selection = ((selection + delta) % count + count) % count
    }

    private func activate(_ items: [Suggestion], at index: Int) {
        if items.indices.contains(index) {
            store.perform(items[index], mode: request.mode)
        } else if let url = URLResolver.resolve(text) {
            store.perform(Suggestion(id: "open", icon: "", title: "", subtitle: nil, action: .open(url)), mode: request.mode)
        }
    }

    private func loadRemoteSuggestions() async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Preferences.showSearchSuggestions, query.count >= 2, URLResolver.directURL(query) == nil else {
            remote = []
            return
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }
        let results = await SearchSuggestions.fetch(query, engine: Preferences.searchEngine)
        guard !Task.isCancelled else { return }
        remote = results
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let favicon = suggestion.favicon {
                    Image(nsImage: favicon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: suggestion.icon).foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.title)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                if let subtitle = suggestion.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let badge = suggestion.badge {
                Text(badge)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: suggestion.subtitle == nil ? 34 : 42)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : .clear)
        )
        .contentShape(Rectangle())
    }
}
