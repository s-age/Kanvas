import AppKit

/// One canvas shape's complete definition — the single file an author adds to introduce a new
/// shape. Pure visual + interaction description; it owns NO domain rule (clamping happens on
/// commit in `ShapeService`). For a closed/box shape, only `kind`/`symbolName`/`label`/`path` are
/// meaningful and `topology` is `.box`; a `.segment` shape ignores `path` (it draws between
/// endpoints) and supplies endpoint handles.
@MainActor
struct ShapeDefinition {
    /// Open visual token — persisted, carried in the palette drag, and matched back on
    /// `ShapeResponse.kind`. Must be stable once shipped (it is stored on disk).
    let kind: String
    /// Behaviour class — picks the canvas draw/hit-test/handle path and is persisted at creation.
    let topology: ShapeTopologyResponse
    /// SF Symbol shown on the palette swatch.
    let symbolName: String
    /// Accessibility / tooltip label (English — see UI-text rule).
    let label: String
    /// Default creation size (re-clamped by the domain `ShapeSize` on commit).
    let defaultWidth: Double
    let defaultHeight: Double
    /// Box shapes: the outline inside a view-space rect (filled then stroked). Segment shapes set
    /// this to a no-op (`{ _ in NSBezierPath() }`) — they never call it.
    let path: (CGRect) -> NSBezierPath
}
