import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        var value: UInt64 = 0
        guard string.count == 6, Scanner(string: string).scanHexInt64(&value) else {
            self.init(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            return
        }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? .gray
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }

    var hexString: String { NSColor(self).hexString }
}
