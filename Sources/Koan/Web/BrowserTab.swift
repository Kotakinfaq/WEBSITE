import AppKit
import SwiftUI
import WebKit

/// One tab. The web view is created lazily and can be dropped again to free
/// memory ("unloading") while the tab keeps its URL, title and history.
@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published private(set) var url: URL?
    @Published var isPinned: Bool
    /// Where a pinned tab or Essential goes back to when it is reset.
    @Published var pinnedURL: URL?
    @Published private(set) var favicon: NSImage?
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoaded = false
    @Published private(set) var isSecure = false
    @Published private(set) var loadError: String?

    weak var store: BrowserStore?
    var lastActive: Date
    private(set) var webView: KoanWebView?
    private var savedInteractionState: Data?
    private var observations: [NSKeyValueObservation] = []
    private var zoom: CGFloat = 1

    init(
        id: UUID = UUID(),
        url: URL?,
        title: String = "",
        isPinned: Bool = false,
        pinnedURL: URL? = nil,
        interactionState: Data? = nil,
        lastActive: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.isPinned = isPinned
        self.pinnedURL = pinnedURL
        self.savedInteractionState = interactionState
        self.lastActive = lastActive
        super.init()
        favicon = FaviconCache.shared.cached(forHost: url?.host)
    }

    /// A tab for a page that opened a new window; WebKit requires the web view
    /// to be built from the configuration it hands us.
    convenience init(configuration: WKWebViewConfiguration, store: BrowserStore) {
        self.init(url: nil)
        self.store = store
        install(makeWebView(configuration: configuration))
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = URLResolver.displayHost(url) { return host }
        return "New Tab"
    }

    var hasNavigatedAwayFromPinnedURL: Bool {
        guard let pinnedURL, let url else { return false }
        return pinnedURL.host != url.host
    }

    var interactionStateForSaving: Data? {
        (webView?.interactionState as? Data) ?? savedInteractionState
    }

    // MARK: Lifecycle

    @discardableResult
    func ensureWebView() -> KoanWebView {
        if let webView { return webView }
        let webView = makeWebView(configuration: WebKitFactory.makeConfiguration())
        install(webView)
        if let state = savedInteractionState {
            webView.interactionState = state
            savedInteractionState = nil
        } else if let url {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func unload() {
        guard let webView else { return }
        savedInteractionState = webView.interactionState as? Data
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.onFocus = nil
        webView.removeFromSuperview()
        self.webView = nil
        isLoaded = false
        isLoading = false
        progress = 0
    }

    func resetToPinnedURL(unload shouldUnload: Bool) {
        guard let pinnedURL else { return }
        if shouldUnload {
            unload()
            savedInteractionState = nil
            url = pinnedURL
            title = ""
            loadError = nil
            favicon = FaviconCache.shared.cached(forHost: pinnedURL.host) ?? favicon
        } else {
            load(pinnedURL)
        }
    }

    private func makeWebView(configuration: WKWebViewConfiguration) -> KoanWebView {
        let webView = KoanWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        return webView
    }

    private func install(_ webView: KoanWebView) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.pageZoom = zoom
        webView.onFocus = { [weak self] in
            guard let self else { return }
            self.store?.webViewDidFocus(self)
        }
        self.webView = webView
        observations = [
            webView.observe(\.title) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.url) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.isLoading) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.canGoBack) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.canGoForward) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.hasOnlySecureContent) { [weak self] _, _ in self?.scheduleSync() },
        ]
        // Deferred: this can run while SwiftUI is updating a view.
        Task { [weak self] in self?.syncState() }
    }

    nonisolated private func scheduleSync() {
        Task { @MainActor [weak self] in self?.syncState() }
    }

    private func syncState() {
        let loaded = webView != nil
        if isLoaded != loaded { isLoaded = loaded }
        guard let webView else { return }
        if let newTitle = webView.title, !newTitle.isEmpty, newTitle != title {
            title = newTitle
            store?.history.updateTitle(newTitle, for: webView.url)
        }
        if let newURL = webView.url, newURL != url { url = newURL }
        if isLoading != webView.isLoading { isLoading = webView.isLoading }
        if progress != webView.estimatedProgress { progress = webView.estimatedProgress }
        if canGoBack != webView.canGoBack { canGoBack = webView.canGoBack }
        if canGoForward != webView.canGoForward { canGoForward = webView.canGoForward }
        let secure = webView.hasOnlySecureContent && webView.url?.scheme == "https"
        if isSecure != secure { isSecure = secure }
    }

    // MARK: Navigation

    func load(_ url: URL) {
        self.url = url
        loadError = nil
        savedInteractionState = nil
        if let webView {
            webView.load(URLRequest(url: url))
        } else {
            ensureWebView()
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func stopLoading() { webView?.stopLoading() }

    func reload() {
        loadError = nil
        guard let webView else { ensureWebView(); return }
        if webView.url == nil, let url {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
    }

    func reloadFromOrigin() {
        loadError = nil
        webView?.reloadFromOrigin()
    }

    func zoomIn() { setZoom(zoom + 0.1) }
    func zoomOut() { setZoom(zoom - 0.1) }
    func resetZoom() { setZoom(1) }

    private func setZoom(_ value: CGFloat) {
        zoom = min(max((value * 10).rounded() / 10, 0.3), 3)
        webView?.pageZoom = zoom
    }

    // MARK: Favicons

    private static let faviconScript = """
    (() => {
      const links = Array.from(document.querySelectorAll(
        'link[rel~="icon"], link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"]'));
      const usable = links.filter(l => l.href && l.type !== 'image/svg+xml' && !/\\.svg(\\?|#|$)/i.test(l.href));
      const size = l => {
        const m = ((l.sizes && l.sizes.value) || '').match(/(\\d+)x/);
        const s = m ? parseInt(m[1], 10) : (l.rel.includes('apple') ? 180 : 32);
        return s > 256 ? 64 : s;
      };
      usable.sort((a, b) => size(b) - size(a));
      return usable.length ? usable[0].href : null;
    })()
    """

    private func fetchFavicon() {
        guard let webView, let pageURL = webView.url, let host = pageURL.host,
              pageURL.scheme == "http" || pageURL.scheme == "https" else { return }
        if let cached = FaviconCache.shared.cached(forHost: host), favicon !== cached { favicon = cached }
        webView.evaluateJavaScript(Self.faviconScript) { [weak self] result, _ in
            let href = result as? String
            Task { @MainActor [weak self] in
                let iconURL = href.flatMap { URL(string: $0) }
                    ?? URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL
                guard let iconURL, let image = await FaviconCache.shared.fetch(iconURL, host: host) else { return }
                if self?.url?.host == host { self?.favicon = image }
            }
        }
    }

    private func handle(_ error: Error) {
        let error = error as NSError
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        // 102: frame load interrupted (the response became a download). 204: plug-in handled load.
        if error.domain == "WebKitErrorDomain" && (error.code == 102 || error.code == 204) { return }
        if let failingURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL { url = failingURL }
        loadError = error.localizedDescription
    }
}

// MARK: - WKNavigationDelegate

extension BrowserTab: WKNavigationDelegate {
    private static let internalSchemes: Set<String> = ["http", "https", "about", "blob", "data", "file", "javascript"]

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        if navigationAction.navigationType == .linkActivated {
            let flags = navigationAction.modifierFlags
            // ⌥-click: peek at the link in Glance.
            if flags.contains(.option) && !flags.contains(.command) {
                store?.openGlance(url: url, from: self)
                decisionHandler(.cancel)
                return
            }
            // ⌘-click or middle-click: new tab (⇧ brings it to the front).
            if flags.contains(.command) || navigationAction.buttonNumber == 2 {
                store?.openTab(url: url, relatedTo: self, background: !flags.contains(.shift))
                decisionHandler(.cancel)
                return
            }
        }

        if let scheme = url.scheme?.lowercased(), !Self.internalSchemes.contains(scheme) {
            // mailto:, tel:, zoommtg:, … belong to other apps.
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame && !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        if let response = navigationResponse.response as? HTTPURLResponse,
           let disposition = response.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        store?.downloads.track(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        store?.downloads.track(download)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if loadError != nil { loadError = nil }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncState()
        store?.setNeedsSave()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncState()
        fetchFavicon()
        store?.history.record(url: webView.url, title: webView.title ?? "")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - WKUIDelegate

extension BrowserTab: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // target="_blank" and window.open() become tabs.
        store?.openPopup(configuration: configuration, from: self).webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        store?.close(self)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "OK")
        present(alert, in: webView) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert, in: webView) { response in completionHandler(response == .alertFirstButtonReturn) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = makeAlert(message: prompt, frame: frame)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert, in: webView) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            panel.beginSheetModal(for: window) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
    }

    private func makeAlert(message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        let host = frame.securityOrigin.host
        alert.messageText = host.isEmpty ? "This page says" : "\(host) says"
        alert.informativeText = message
        return alert
    }

    private func present(_ alert: NSAlert, in webView: WKWebView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}
