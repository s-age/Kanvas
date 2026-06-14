import Foundation

/// Picks a readable foreground colour — dark `#333` on a light background, soft near-white `#ddd`
/// on a dark one — from a background's perceptual luminance. The single Domain source for the
/// canvas's "#333 / #ddd on a fill or background" auto-contrast: `StickyService` (a sticky's text
/// on its fill) and `ConnectorService` (a connector's stroke on the canvas background) both
/// delegate here, so the two stay in lock-step. Uses the canonical `0.299/0.587/0.114` weights and
/// `0.6` threshold, matching the Presentation pill version in
/// `CanvasNSView+Drawing.readableTextColor(onHex:)` (hand-copied there — no shared layer below
/// Domain to host it). Returns a *concrete* hex so the chosen colour is baked in at creation, not
/// recomputed on render. Distinct from `Shared/Color+Hex.readableForeground`, which uses the WCAG
/// `0.2126/0.7152/0.0722` weights for opaque SwiftUI swatches.
enum ContrastColor: Sendable {
    /// On-light foreground ("RRGGBB") — a readable dark grey for bright backgrounds. The bright-side
    /// counterpart to `onDarkHex`; also the sticky's default text colour (`StickyTextStyle.defaultColorHex`).
    static let onLightHex = "333333"
    /// On-dark foreground ("RRGGBB") — a soft near-white that reads on a dark background without the
    /// harshness of pure white. The dark-side counterpart to `onLightHex`.
    static let onDarkHex = "DDDDDD"

    /// The foreground hex that reads best on `backgroundHex` ("RRGGBB"): `onLightHex` on a light
    /// background, `onDarkHex` on a dark one. A malformed background falls back to `onLightHex`.
    static func readableHex(onBackground backgroundHex: String) -> String {
        guard let luminance = perceptualLuminance(ofHex: backgroundHex) else { return onLightHex }
        return luminance > 0.6 ? onLightHex : onDarkHex
    }

    /// Perceptual luminance (0...1) of a "RRGGBB" hex, or `nil` if it is not six hex digits. Pure
    /// Foundation so it stays in Domain — the Presentation hex parsers (`NSColor`/`Color(hex:)`)
    /// cannot be reached from here.
    private static func perceptualLuminance(ofHex hex: String) -> Double? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
