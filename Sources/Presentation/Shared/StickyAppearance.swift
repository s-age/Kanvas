import Foundation

/// Presentation-side mirrors of sticky text-style / size constants carried in `StickyResponse`.
/// Kept as literals (not referencing the Domain entity) so Presentation stays within its import
/// boundary; the Domain entity remains the authoritative source (pinned by parity tests).
enum StickyAppearance {
    // Default sticky text colour — mirrors the Domain `StickyTextStyle.defaultColorHex`. Used as
    // the Settings "Default Text" picker's starting value. (The retired "auto" sentinel is gone:
    // text colour is always a literal hex, with no background-brightness auto-contrast.)
    static let defaultTextColorHex = "333333"
    // Font-size bounds for the toolbar stepper. Mirror the Domain `StickyTextStyle` clamp
    // (Presentation cannot import the entity); the entity remains the authoritative clamp.
    static let minFontSize: Double = 8
    static let maxFontSize: Double = 48
    // Sticky-size bounds for the Settings → Canvas steppers. Mirror the Domain `StickySize`
    // clamp; the entity remains the authoritative clamp on every domain entry.
    static let minStickyWidth: Double = 80
    static let maxStickyWidth: Double = 2000
    static let minStickyHeight: Double = 60
    static let maxStickyHeight: Double = 2000
    // Upper bound on a sticky-preset's width/height — mirrors the Domain `StickyPreset.maxDimension`
    // (tighter than the resize max above). Used to validate the preset-size text fields. The
    // minimums reuse `minStickyWidth`/`minStickyHeight`.
    static let maxPresetDimension: Double = 512
    // Initial-zoom slider bounds. The canvas itself clamps live zoom to this range, so the
    // slider offers no value the canvas cannot actually display (the Domain `CanvasSettings`
    // clamp is wider, 0.1…5.0, and re-clamps on load).
    static let minZoom: Double = 0.25
    static let maxZoom: Double = 4.0
    // Default sticky fill colours (free / task) used when no per-board override is set. The single
    // source shared by the canvas draw-side fallback (`CanvasNSView.tintColor(for:)`) and the
    // Settings → Canvas clearable colour-picker preview, so a "cleared" picker shows exactly the
    // colour the canvas actually draws.
    static let freeStickyDefaultHex = "FFE873"
    static let taskStickyDefaultHex = "AFC8F5"
}
