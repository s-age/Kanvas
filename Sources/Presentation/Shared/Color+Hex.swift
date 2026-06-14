import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }

    /// 6-digit RGB hex (no `#`) for this colour, resolved in `environment`. Used to persist a
    /// `ColorPicker` selection back into the hex-string storage. AppKit-free — `Color.Resolved`
    /// exposes the sRGB components directly, so no `NSColor` round-trip leaks into Presentation.
    func toHex(in environment: EnvironmentValues) -> String {
        let resolved = resolve(in: environment)
        func channel(_ value: Float) -> Int { min(max(Int((value * 255).rounded()), 0), 255) }
        return String(format: "%02X%02X%02X", channel(resolved.red), channel(resolved.green), channel(resolved.blue))
    }

    /// Black or white, whichever reads better on the given "RRGGBB" background — picked by a
    /// perceptual-luminance estimate (0.299/0.587/0.114 weights, threshold 0.6). Used for the label
    /// drawn over a coloured sticky-preset swatch. (Not the WCAG relative-luminance formula; this is
    /// a lightweight approximation sufficient for a 3-character badge.)
    ///
    /// A hex string is a fixed sRGB triple with no light/dark variant, so the resolution environment
    /// is irrelevant here — the default empty environment is correct.
    static func readableForeground(onHex hex: String) -> Color {
        readableForeground(onColor: Color(hex: hex))
    }

    /// Black or white, whichever reads better on the given background `Color` — same
    /// perceptual-luminance estimate as `readableForeground(onHex:)`. Used when the background is
    /// already a `Color` (e.g. a live `ColorPicker` binding) rather than a stored hex string.
    ///
    /// Pass the **live** `environment` (`@Environment(\.self)`) when `color` may be a dynamic system
    /// colour (e.g. `.boardDefaultBackground` / `.boardDefaultText`): resolving in an empty
    /// `EnvironmentValues()` always yields the *light* variant, so a dark-mode swatch would have its
    /// contrast computed against the wrong shade. The default empty environment is fine only for a
    /// fixed-triple colour (e.g. one built from a hex string).
    static func readableForeground(
        onColor color: Color,
        in environment: EnvironmentValues = EnvironmentValues()
    ) -> Color {
        let bg = color.resolve(in: environment)
        let luminance = 0.299 * Double(bg.red) + 0.587 * Double(bg.green) + 0.114 * Double(bg.blue)
        return luminance > 0.6 ? .black : .white
    }

    // MARK: - Board default colors (single source of truth)

    static var boardDefaultBackground: Color { Color(.windowBackgroundColor) }
    static var boardDefaultText: Color { .primary }
    /// Resting background of a Kanban card when no `cardBackgroundColorHex` override is set.
    /// Shared by the board view and the Board settings colour picker so the two never drift.
    static var boardDefaultCardBackground: Color { Color(.textBackgroundColor) }
    /// Fixed neutral colour for a card's status-indicator dot when the column sets no
    /// `indicatorColorHex`. The dot no longer follows the card's status colour — an unset column
    /// renders a neutral grey here. Shared by the board view and the Board settings picker default.
    static var boardDefaultStatusDot: Color { .secondary }
}
