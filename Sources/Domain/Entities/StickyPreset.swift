import Foundation

/// A user-managed sticky preset offered in the canvas palette (Miro-style drag-to-create).
/// Each preset carries its own short `label`, fill `colorHex`, and an absolute `width`/`height`
/// — dragging one onto the canvas creates a sticky of that size and background colour. The set is
/// editable in Settings → Canvas (add / remove / recolour / resize), scoped per board + the
/// Default template. Seeded with S / M / L.
///
/// `label` is trimmed to at most 3 characters and `width`/`height` are clamped to `StickySize`'s
/// bounds in the initializer — both are domain rules, so a hand-edited out-of-range value is
/// re-normalised on load (every entry routes through `init`).
struct StickyPreset: Sendable, Identifiable, Equatable {
    /// The longest a preset label may be — the palette swatch is too small to read more.
    static let maxLabelLength = 3

    /// Upper bound on a preset's width/height. Tighter than `StickySize.max…` (2000) on purpose:
    /// a *created* sticky should start at a sane size, while a free resize on the canvas may still
    /// grow it up to `StickySize`'s bounds. The lower bounds reuse `StickySize.min…`.
    static let maxDimension: Double = 512

    /// The seed/fallback fill colour ("RRGGBB"). Single source for the S/M/L `defaultPresets` and
    /// for `BoardSnapshotMapper`'s recovery of a partial persisted preset, so the two never drift.
    static let defaultFillHex = "FFE873"

    let id: UUID
    var label: String
    var colorHex: String
    var width: Double
    var height: Double

    init(id: UUID = UUID(), label: String, colorHex: String, width: Double, height: Double) {
        self.id = id
        self.label = String(label.prefix(StickyPreset.maxLabelLength))
        self.colorHex = colorHex
        self.width = min(max(width, StickySize.minWidth), StickyPreset.maxDimension)
        self.height = min(max(height, StickySize.minHeight), StickyPreset.maxDimension)
    }

    /// The seed presets a board starts with. Sizes preserve the former S/M/L ratios
    /// (0.84 / 1.0 / 1.2 of the old 200×150 default); colour matches the previous uniform
    /// free-sticky fill (`StickyAppearance.freeStickyDefaultHex`).
    static let defaultPresets: [StickyPreset] = [
        StickyPreset(label: "S", colorHex: defaultFillHex, width: 168, height: 126),
        StickyPreset(label: "M", colorHex: defaultFillHex, width: 200, height: 150),
        StickyPreset(label: "L", colorHex: defaultFillHex, width: 240, height: 180),
    ]
}
