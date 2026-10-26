import SwiftUI

struct WorkspaceEditor: View {
    @ObservedObject var workspace: Workspace
    let store: BrowserStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workspace").font(.title3.weight(.semibold))

            HStack(spacing: 10) {
                TextField("", text: $workspace.icon)
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                TextField("Name", text: $workspace.name)
            }
            .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 10), spacing: 6) {
                ForEach(Workspace.suggestedIcons, id: \.self) { icon in
                    Text(icon)
                        .font(.system(size: 16))
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(workspace.icon == icon ? 0.15 : 0.04))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { workspace.icon = icon }
                }
            }

            Text("Theme").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 10), spacing: 8) {
                ForEach(WorkspaceTheme.presets, id: \.self) { theme in
                    Circle()
                        .fill(theme.gradient)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(workspace.theme == theme ? 0.8 : 0.1), lineWidth: 2))
                        .contentShape(Circle())
                        .onTapGesture { workspace.theme = theme }
                }
            }

            HStack(spacing: 20) {
                ColorPicker("Primary", selection: colorBinding(\.primary), supportsOpacity: false)
                ColorPicker("Secondary", selection: colorBinding(\.secondary), supportsOpacity: false)
            }

            HStack {
                Button("Delete Workspace", role: .destructive) {
                    dismiss()
                    store.deleteWorkspace(workspace)
                }
                .disabled(store.workspaces.count < 2)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 400)
        .onChange(of: workspace.icon) { icon in
            // One emoji (or character) only: keep the one just typed.
            if icon.count > 1 { workspace.icon = String(icon.suffix(1)) }
        }
        .onDisappear { store.setNeedsSave() }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<WorkspaceTheme, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: workspace.theme[keyPath: keyPath]) },
            set: { workspace.theme[keyPath: keyPath] = $0.hexString }
        )
    }
}

struct DownloadsList: View {
    @ObservedObject var downloads: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                if downloads.items.contains(where: { $0.state != .downloading }) {
                    Button("Clear") { downloads.clearFinished() }
                        .buttonStyle(.borderless)
                }
            }
            .padding(12)

            Divider()

            if downloads.items.isEmpty {
                Text("No downloads yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(downloads.items) { item in
                            DownloadRow(item: item)
                            Divider().opacity(0.5)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 320)
    }
}

private struct DownloadRow: View {
    @ObservedObject var item: DownloadItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                switch item.state {
                case .downloading:
                    ProgressView(value: item.fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                case .finished:
                    Text("Done").font(.caption).foregroundStyle(.secondary)
                case .failed(let reason):
                    Text(reason).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.state == .downloading {
                IconButton(systemName: "xmark.circle", help: "Cancel") { item.cancel() }
            } else if item.state == .finished {
                IconButton(systemName: "magnifyingglass", help: "Show in Finder") { item.reveal() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { item.open() }
    }
}
