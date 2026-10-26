import AppKit
import SwiftUI
import WebKit

/// Hosts a tab's web view. The web view belongs to the tab, so switching tabs
/// swaps the subview instead of reloading anything.
struct WebViewHost: NSViewRepresentable {
    let tab: BrowserTab
    /// Changes when the tab loads or unloads, so SwiftUI calls `updateNSView`.
    let isLoaded: Bool

    func makeNSView(context: Context) -> WebContainerView {
        let view = WebContainerView()
        view.host(tab.ensureWebView())
        return view
    }

    func updateNSView(_ view: WebContainerView, context: Context) {
        view.host(tab.ensureWebView())
    }

    static func dismantleNSView(_ view: WebContainerView, coordinator: ()) {
        view.releaseWebView()
    }
}

final class WebContainerView: NSView {
    private weak var hosted: WKWebView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func host(_ webView: WKWebView) {
        if hosted === webView, webView.superview === self { return }
        if let hosted, hosted.superview === self { hosted.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        hosted = webView
    }

    func releaseWebView() {
        if let hosted, hosted.superview === self { hosted.removeFromSuperview() }
        hosted = nil
    }
}

/// The window backdrop: vibrancy plus the workspace gradient. Empty areas of
/// the window drag it, and a double-click zooms, as in a title bar.
struct WorkspaceBackdrop: NSViewRepresentable {
    let colors: [NSColor]

    func makeNSView(context: Context) -> BackdropView {
        let view = BackdropView()
        view.apply(colors: colors, animated: false)
        return view
    }

    func updateNSView(_ view: BackdropView, context: Context) {
        view.apply(colors: colors, animated: true)
    }
}

final class BackdropView: NSView {
    private let effect = NSVisualEffectView()
    private let gradientHost = NSView()
    private let gradient = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        effect.frame = bounds
        effect.autoresizingMask = [.width, .height]
        addSubview(effect)

        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradientHost.layer = gradient
        gradientHost.wantsLayer = true
        gradientHost.frame = bounds
        gradientHost.autoresizingMask = [.width, .height]
        addSubview(gradientHost)
        updateOpacity()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func apply(colors: [NSColor], animated: Bool) {
        let newColors = colors.map { $0.cgColor }
        let oldColors = gradient.colors as? [CGColor]
        guard oldColors != newColors else { return }
        if animated, let oldColors {
            let animation = CABasicAnimation(keyPath: "colors")
            animation.fromValue = oldColors
            animation.toValue = newColors
            animation.duration = 0.35
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradient.add(animation, forKey: "colors")
        }
        gradient.colors = newColors
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateOpacity()
    }

    private func updateOpacity() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        gradientHost.alphaValue = dark ? 0.42 : 0.72
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// Calls back with the hosting window once the view is in one.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: WindowObservingView, context: Context) {
        view.onWindow = onWindow
    }
}

final class WindowObservingView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow?(window) }
    }
}

/// A borderless text field with arrow-key, Return and Esc callbacks, used by
/// the command bar and the find bar.
struct CommandTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 16
    /// Bump to pull keyboard focus back into the field.
    var focusRequest: Int = 0
    var onSubmit: (NSEvent.ModifierFlags) -> Void
    var onMove: (Int) -> Void = { _ in }
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> AutoFocusTextField {
        let field = AutoFocusTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.placeholderString = placeholder
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingTail
        field.stringValue = text
        field.delegate = context.coordinator
        context.coordinator.lastFocusRequest = focusRequest
        return field
    }

    func updateNSView(_ field: AutoFocusTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            field.focus()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandTextField
        var lastFocusRequest = 0

        init(parent: CommandTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(NSApp.currentEvent?.modifierFlags ?? [])
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

final class AutoFocusTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focus()
    }

    func focus() {
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
}
