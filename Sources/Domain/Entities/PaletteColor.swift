import Foundation

/// A single user-managed colour in the Global colour palette. Each entry carries a fill
/// `colorHex` ("RRGGBB") and an optional, free-text `label` (a human name like "Accent" /
/// "Warning"). The palette is an ordered list edited in Settings → Global (add / remove /
/// recolour / relabel / reorder), scoped per board + the Default template (the same scope
/// behaviour as the rest of `GlobalSettings`).
///
/// The palette exists so the app can offer a small, curated set of recurring colours and lean
/// on the OS colour picker only when *editing* the palette — not at every colour-choosing site.
///
/// Both `colorHex` and `label` are normalised in the initializer (domain rules): `colorHex` is
/// validated to a 6-digit "RRGGBB" hex (anything else — empty, malformed, a partial/corrupt
/// persisted entry — falls back to `defaultColorHex`), and `label` is trimmed to at most
/// `maxLabelLength` characters. Every entry routes through `init` (the mapper passes the raw
/// persisted value straight through), so a hand-edited JSON value is re-validated on load — the
/// "persisted value is untrusted input" rule.
struct PaletteColor: Sendable, Identifiable, Equatable {
    /// The longest a palette label may be — long enough for a descriptive name, capped so a
    /// hand-edited persisted blob can't carry an unbounded string.
    static let maxLabelLength = 40

    /// Fallback fill when a persisted/edited `colorHex` is not a valid 6-digit hex.
    static let defaultColorHex = "000000"

    let id: UUID
    var colorHex: String
    var label: String

    init(id: UUID = UUID(), colorHex: String, label: String = "") {
        self.id = id
        self.colorHex = PaletteColor.normalizedColorHex(colorHex)
        self.label = String(label.prefix(PaletteColor.maxLabelLength))
    }

    /// Validates a fill colour to a 6-digit "RRGGBB" hex. A leading "#" is stripped; any value that
    /// is not exactly six hex digits falls back to `defaultColorHex`. The single validation site for
    /// a palette colour — keeps the "invalid → black" decision a domain rule rather than a mapper
    /// fallback.
    static func normalizedColorHex(_ hex: String) -> String {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        let isSixHexDigits = value.count == 6 && value.allSatisfy(\.isHexDigit)
        return isSixHexDigits ? value : defaultColorHex
    }

    /// The seed palette a board / the template starts with. Mirrors the fixed colour set the
    /// canvas shape & connector toolbars have always offered (Black / Gray / Red / Orange / Green /
    /// Blue / Purple / White) — single-sourced here so a future migration of those toolbars to the
    /// managed palette starts from the identical colours.
    static let defaultPalette: [PaletteColor] = [
        PaletteColor(colorHex: "000000", label: "Black"),
        PaletteColor(colorHex: "8E8E93", label: "Gray"),
        PaletteColor(colorHex: "FF3B30", label: "Red"),
        PaletteColor(colorHex: "FF9500", label: "Orange"),
        PaletteColor(colorHex: "34C759", label: "Green"),
        PaletteColor(colorHex: "007AFF", label: "Blue"),
        PaletteColor(colorHex: "AF52DE", label: "Purple"),
        PaletteColor(colorHex: "FFFFFF", label: "White"),
    ]
}
