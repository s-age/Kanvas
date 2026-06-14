import Foundation

/// A shape-creation request crossing from the canvas to the ViewModel: where it drops (`worldX`/
/// `worldY` centre) plus its default size and shape identity (`kind` + `topology`). Bundling the
/// six primitives that threaded identically through `CanvasActionHandler.addShape` →
/// `BoardViewModel.addShape` keeps both APIs to a single argument (parent ticket 087D2E6C
/// candidate A). A ViewModel-facing vocabulary type carrying no AppKit value type, so it lives in
/// `Shared/` rather than the AppKit-permitted `Canvas/` folder — mirrors `CanvasDragMove`.
struct ShapeDraft: Sendable, Equatable {
    /// World-space centre the dropped shape takes.
    let worldX: Double
    let worldY: Double
    /// Open visual token from the canvas shape registry (e.g. "rectangle" / "triangle").
    let kind: String
    /// Behaviour class — `box` | `segment`. Persisted at creation; drives handles / hit-testing.
    let topology: ShapeTopologyResponse
    /// Default creation size (re-clamped by the domain `ShapeSize` on commit).
    let defaultWidth: Double
    let defaultHeight: Double
}
