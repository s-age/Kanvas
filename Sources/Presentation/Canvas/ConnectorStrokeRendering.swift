import AppKit

// MARK: - Stroke colour gate

/// The draw-time half of the connector stroke "unset" representation. A small Canvas-local namespace
/// so the `NSColor`-returning helper stays scoped to this AppKit carve-out rather than a bare
/// module-level symbol, while remaining `internal` for `ConnectorStrokeColorGateTests`.
enum ConnectorStrokeRendering {
    /// A non-selected connector's drawn stroke colour. The Optional stroke *is* the unset signal:
    /// - `nil` ⇒ **unset** → `adaptiveDefault` (`#333`/`#ddd` resolved once per draw pass from the
    ///   live background — see `adaptiveDefaultStrokeColor`). A connector lands here when it was
    ///   created with no explicit colour on a nil-background board (`ConnectorService` stores `nil`),
    ///   or cleared back to unset via the toolbar; a configured-background board baked `#333`/`#ddd`
    ///   at creation, so its stroke is non-nil and skips this branch.
    /// - a present hex ⇒ explicit pick, rendered verbatim — **including pure `#000000`**. This is the
    ///   fix the end-to-end Optional buys: the old non-optional `#000` sentinel could not distinguish
    ///   an explicitly-chosen black from "never set", so a nil-background board re-contrasted it away.
    static func strokeColor(forHex strokeColorHex: String?, adaptiveDefault: NSColor) -> NSColor {
        guard let strokeColorHex else { return adaptiveDefault }
        return NSColor(hex: strokeColorHex)
    }
}
