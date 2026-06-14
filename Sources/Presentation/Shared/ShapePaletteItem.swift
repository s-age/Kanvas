import Foundation

/// Pure-Swift projection of a `ShapeDefinition` for the palette view. Contains no AppKit types
/// or closures — safe to use in any SwiftUI view outside the Canvas/ carve-out. The full
/// `ShapeDefinition` (with its `path` closure) stays inside Canvas/ and is AppKit-only.
struct ShapePaletteItem: Sendable {
    /// Open visual token — matches `ShapeResponse.kind` and is used as the drag payload seed.
    let kind: String
    /// SF Symbol name for the palette swatch icon.
    let symbolName: String
    /// Accessibility / tooltip label (English).
    let label: String
    let defaultWidth: Double
    let defaultHeight: Double
}

extension ShapePaletteItem: Identifiable {
    var id: String { kind }
}
