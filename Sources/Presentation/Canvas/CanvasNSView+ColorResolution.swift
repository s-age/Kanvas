import AppKit

// MARK: - Sticky colour resolution (fill / tint / luminance / text)
//
// Split into a same-folder extension so the main `CanvasNSView` body stays within the file-length
// budget. Resolves a sticky's drawn colours — base tint, composited (flattened) fill, perceptual
// luminance, and literal text colour — shared by sticky drawing, the connector stroke pick, and the
// inline editor's background/foreground colours.

extension CanvasNSView {

    /// Opacity applied to a sticky's tint over the canvas background. Kept high (near-opaque) so the
    /// rendered fill closely matches the chosen colour rather than a washed-out, near-black blend —
    /// which is also what makes the raw-hex auto-contrast (`ContrastColor.readableHex`) read
    /// true, since the text is contrasted against the colour the eye actually sees. Task stickies sit
    /// a touch lighter so the linked-card cue still reads through. The single source for both the
    /// drawn fill (`CanvasNSView+Drawing`) and the flattened editor background.
    func tintFraction(for sticky: StickyResponse) -> CGFloat {
        sticky.isTask ? 0.75 : 0.85
    }

    /// The sticky's base tint colour — the board's configured free/task fill colour, or the
    /// built-in default (`StickyAppearance.free/taskStickyDefaultHex`) when unset. That fallback is
    /// the same hex the Settings picker shows when cleared, so the picker preview matches what is
    /// drawn. Single source for drawing + editing.
    func tintColor(for sticky: StickyResponse) -> NSColor {
        // A per-sticky fill (set from the palette preset at creation) wins over every board default.
        if let perSticky = sticky.fillColorHex {
            return NSColor(hex: perSticky)
        }
        let override = sticky.isTask ? canvasSettings?.taskStickyColorHex : canvasSettings?.freeStickyColorHex
        // The fallback hex matches the Settings picker's "cleared" preview (single source in
        // `StickyAppearance`), so clearing an override draws exactly what the picker shows.
        let hex = override ?? (sticky.isTask
            ? StickyAppearance.taskStickyDefaultHex
            : StickyAppearance.freeStickyDefaultHex)
        return NSColor(hex: hex)
    }

    /// Opaque colour matching the composited sticky fill (translucent tint over the window
    /// background) — used as the editor's background so editing keeps the sticky's colour.
    func flattenedFill(for sticky: StickyResponse) -> NSColor {
        let base = canvasBackgroundColor.usingColorSpace(.sRGB) ?? .windowBackgroundColor
        return base.blended(withFraction: tintFraction(for: sticky), of: tintColor(for: sticky)) ?? base
    }

    /// Perceptual luminance (0...1) of `color`, using the canonical `0.299/0.587/0.114` weights —
    /// the Presentation copy of `ContrastColor.perceptualLuminance` (Domain is unreachable here).
    /// Converts to sRGB first; a non-convertible (catalog) colour falls back to `.black`, a
    /// known-RGB colour, so the `.redComponent`/… reads never raise on a dynamic colour. Shared by
    /// the connector stroke pick (`CanvasNSView+Connectors`) and the label-pill text pick
    /// (`CanvasNSView+Drawing.readableTextColor`) so the formula lives in one place in this folder.
    func perceptualLuminance(of color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    }

    /// The sticky's literal text colour. Every sticky carries a concrete `textColorHex` (a new one
    /// bakes the canvas default at creation; legacy "auto" values were migrated to the default on
    /// load), so this is a direct hex → colour conversion — there is no background-brightness
    /// auto-contrast and no Global-default cascade for sticky text.
    func effectiveTextColor(for sticky: StickyResponse) -> NSColor {
        NSColor(hex: sticky.textColorHex)
    }
}
