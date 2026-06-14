import AppKit

extension NSColor {
    /// Builds an sRGB colour from a 6-digit hex string ("RRGGBB"); falls back to black on a
    /// malformed value. Mirrors `Shared/Color+Hex.swift` for the AppKit-only surfaces (which
    /// cannot import SwiftUI's `Color`).
    ///
    /// Shared by both AppKit carve-outs — the Canvas (sticky fills) and the Markdown editor
    /// (`MarkdownTheme` code/quote colours). It physically lives under `Canvas/` only because
    /// AppKit imports are lint-restricted to the `Canvas/` and `Views/Markdown/` folders, leaving
    /// no neutral home; module-internal scope makes it reachable from both. Treat it as a shared
    /// AppKit helper, not Canvas-private — removing/renaming this init breaks the Markdown editor.
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        if cleaned.count == 6 {
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        } else {
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}
