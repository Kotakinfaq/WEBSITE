import AppKit
import WebKit

enum WebKitFactory {
    /// Appended to WebKit's user agent so sites treat Koan like Safari.
    static let applicationName = "Version/18.0 Safari/605.1.15"

    @MainActor
    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = applicationName
        configuration.preferences.isElementFullscreenEnabled = true
        // Adds "Inspect Element" to the page context menu.
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        return configuration
    }
}

/// WKWebView that reports when it takes keyboard focus (used to switch the
/// focused pane in split view) and speaks in tabs rather than windows.
final class KoanWebView: WKWebView {
    var onFocus: (@MainActor () -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items {
            switch item.identifier?.rawValue {
            case "WKMenuItemIdentifierOpenLinkInNewWindow":
                item.title = "Open Link in New Tab"
            case "WKMenuItemIdentifierOpenImageInNewWindow":
                item.title = "Open Image in New Tab"
            case "WKMenuItemIdentifierOpenMediaInNewWindow":
                item.title = "Open Video in New Tab"
            case "WKMenuItemIdentifierOpenFrameInNewWindow":
                item.title = "Open Frame in New Tab"
            default:
                break
            }
        }
    }
}
