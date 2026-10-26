import AppKit
import WebKit

@MainActor
final class DownloadItem: ObservableObject, Identifiable {
    enum State: Equatable {
        case downloading
        case finished
        case failed(String)
    }

    let id = UUID()
    @Published var filename: String
    @Published var destination: URL?
    @Published var fraction: Double = 0
    @Published var state: State = .downloading

    fileprivate var download: WKDownload?
    fileprivate var observation: NSKeyValueObservation?

    init(filename: String) {
        self.filename = filename
    }

    func cancel() {
        download?.cancel { _ in }
    }

    func reveal() {
        guard let destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func open() {
        guard let destination else { return }
        NSWorkspace.shared.open(destination)
    }
}

/// Saves downloads to ~/Downloads and tracks their progress.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    @Published var hasUnseenActivity = false

    private var itemsByDownload: [ObjectIdentifier: DownloadItem] = [:]

    var activeCount: Int { items.filter { $0.state == .downloading }.count }

    func track(_ download: WKDownload) {
        download.delegate = self
        let item = DownloadItem(filename: download.originalRequest?.url?.lastPathComponent ?? "Download")
        item.download = download
        item.observation = download.progress.observe(\.fractionCompleted) { [weak item] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor [weak item] in item?.fraction = fraction }
        }
        itemsByDownload[ObjectIdentifier(download)] = item
        items.insert(item, at: 0)
        hasUnseenActivity = true
    }

    func clearFinished() {
        items.removeAll { $0.state != .downloading }
    }

    private func finish(_ download: WKDownload, state: DownloadItem.State) {
        guard let item = itemsByDownload.removeValue(forKey: ObjectIdentifier(download)) else { return }
        item.state = state
        if state == .finished { item.fraction = 1 }
        item.observation = nil
        item.download = nil
        hasUnseenActivity = true
    }

    private static func uniqueDestination(for filename: String) -> URL {
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = filename.isEmpty ? "Download" : filename
        var candidate = directory.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            counter += 1
            let numbered = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
        }
        return candidate
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let destination = Self.uniqueDestination(for: suggestedFilename)
        if let item = itemsByDownload[ObjectIdentifier(download)] {
            item.filename = destination.lastPathComponent
            item.destination = destination
        }
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let destination = itemsByDownload[ObjectIdentifier(download)]?.destination
        finish(download, state: .finished)
        if let destination {
            // Bounces the Downloads stack in the Dock, like Safari.
            DistributedNotificationCenter.default().post(
                name: Notification.Name("com.apple.DownloadFileFinished"),
                object: destination.path
            )
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(download, state: .failed(error.localizedDescription))
    }
}
