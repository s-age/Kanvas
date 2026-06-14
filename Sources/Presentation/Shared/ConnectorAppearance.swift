import Foundation

/// Presentation-side connector adaptive-contrast pair. Kept as literals (not referencing Domain
/// `ContrastColor`) so Presentation stays within its import boundary; the Domain contrast values
/// remain authoritative, pinned by `ConnectorAppearanceParityTests`. "Unset" carries no literal of
/// its own — it is the Optional stroke being `nil` (see `ConnectorStrokeRendering.strokeColor`).
enum ConnectorAppearance {
    /// On-light / on-dark adaptive stroke for an unset connector over a system background — mirror
    /// Domain `ContrastColor.onLightHex` / `onDarkHex` (`#333` reads on a light appearance, `#ddd` on
    /// a dark one). Resolved at draw time from the live `windowBackgroundColor` luminance.
    static let onLightStrokeHex = "333333"
    static let onDarkStrokeHex = "DDDDDD"
}
