import Foundation

/// Text appearance of a sticky's content — colour + size, editable from the canvas toolbar.
/// Both `colorHex` and `fontSize` are normalised in the initializer (domain rules): the retired
/// `"auto"` sentinel is coerced to the concrete default colour, and `fontSize` is clamped to
/// `[minFontSize, maxFontSize]`. Every domain entry routes through it — `settingFontSize(...)` on
/// write and `BoardSnapshotMapper.toEntities` on load — so a hand-edited or legacy JSON value is
/// re-validated on read (the "persisted value is untrusted input" rule). (Persistence is via
/// `StickyDTO`, so this type needs no `Codable`.)
struct StickyTextStyle: Sendable, Equatable {
    static let minFontSize: Double = 8
    static let maxFontSize: Double = 48
    /// Default text colour ("RRGGBB") — a readable dark grey. Also the text colour a sticky inherits
    /// when it has no explicit fill. Sourced from `ContrastColor.onLightHex` (same dark grey), which
    /// owns the auto-contrast pair the canvas picks from for fills/backgrounds.
    static let defaultColorHex = ContrastColor.onLightHex
    static let defaultFontSize: Double = 13
    /// The retired sentinel older snapshots stored for "pick text colour from background
    /// brightness". That feature is gone, so it is coerced to `defaultColorHex` on every entry.
    private static let legacyAutoSentinel = "auto"

    var colorHex: String
    var fontSize: Double

    init(colorHex: String = StickyTextStyle.defaultColorHex,
         fontSize: Double = StickyTextStyle.defaultFontSize) {
        self.colorHex = StickyTextStyle.normalizedColorHex(colorHex)
        self.fontSize = min(max(fontSize, StickyTextStyle.minFontSize), StickyTextStyle.maxFontSize)
    }

    /// Coerces the retired `"auto"` sentinel (any casing) to the concrete default; any other value
    /// passes through as a literal hex. The single source for this migration rule — `CanvasSettings`
    /// reuses it for its default text colour, and `BoardSnapshotMapper` relies on `init` calling it.
    static func normalizedColorHex(_ hex: String) -> String {
        hex.caseInsensitiveCompare(legacyAutoSentinel) == .orderedSame ? defaultColorHex : hex
    }

    static let `default` = StickyTextStyle()
}
