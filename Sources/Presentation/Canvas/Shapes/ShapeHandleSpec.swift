import AppKit

/// One draggable handle on a selected shape. The canvas iterates `ShapeRegistry.defaultHandles(for:)`
/// for the selected shape's topology — box → one corner handle, segment → two endpoint handles — so
/// a future shape with a novel handle layout supplies its own array without touching the canvas
/// drag loop. `position` locates the handle (works in either view or world space — it only picks a
/// corner/endpoint); `requestedDrag` maps a drag to the requested raw geometry.
@MainActor
struct ShapeHandleSpec {
    /// View-space centre of the handle, given the shape's current view-space frame and its two
    /// segment endpoints (endpoints are only meaningful for `.segment`; box handles ignore them).
    let position: (_ viewFrame: CGRect, _ endpoints: (start: CGPoint, end: CGPoint)) -> CGPoint
    /// Given this handle dragged to `toWorld` with the shape's current world frame + endpoints,
    /// return the requested new **world** frame and (segment only) the new `rising` flag. PURE
    /// interaction geometry — never clamp here; the domain clamps on commit.
    let requestedDrag: (_ toWorld: CGPoint,
                        _ currentWorldFrame: CGRect,
                        _ worldEndpoints: (start: CGPoint, end: CGPoint)) -> ShapeDragRequest
}

/// The raw result of dragging a handle — fed to `resizeShape(frame:lineRising:)` on commit.
struct ShapeDragRequest {
    let worldFrame: CGRect
    /// Segment endpoint drag sets this (`rising(from:to:)`); box corner resize leaves it nil.
    let rising: Bool?
}
