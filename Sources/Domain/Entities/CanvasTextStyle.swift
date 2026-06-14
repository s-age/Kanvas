import Foundation

/// Text appearance of a free-text object — colour + size. A free-text object has **no background
/// and no border** (unlike a sticky), so the only style fields are the text colour and font size.
/// `fontSize` is clamped to `[minFontSize, maxFontSize]` in the initializer (a domain rule). Every
/// domain entry routes through it — `settingFontSize(...)` on write and `BoardSnapshotMapper.toEntities`
/// on load — so a hand-edited or legacy JSON value is re-validated on read (the "persisted value is
/// untrusted input" rule). (Persistence is via `TextDTO`, so this type needs no `Codable`.)
///
/// A dedicated type, **not** `StickyTextStyle`: the two carry the same fields today, but a free-text
/// object is a distinct concept with no fill/contrast coupling, so keeping the style independent lets
/// either evolve without dragging the other along (ticket 7C1D6316 決め事 1).
struct CanvasTextStyle: Sendable, Equatable {
    static let minFontSize: Double = 8
    static let maxFontSize: Double = 96
    /// Default text colour ("RRGGBB") — a readable dark grey, shared with the sticky default so a
    /// free-text object reads at the same weight as sticky text on a light canvas.
    static let defaultColorHex = ContrastColor.onLightHex
    static let defaultFontSize: Double = 16

    var colorHex: String
    var fontSize: Double

    init(colorHex: String = CanvasTextStyle.defaultColorHex,
         fontSize: Double = CanvasTextStyle.defaultFontSize) {
        self.colorHex = colorHex
        self.fontSize = min(max(fontSize, CanvasTextStyle.minFontSize), CanvasTextStyle.maxFontSize)
    }

    static let `default` = CanvasTextStyle()
}
