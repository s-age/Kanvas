import Foundation

/// One item's target world centre in a group move — the canvas computes each member's destination
/// (its original centre + the shared, snapped drag delta) and hands the batch to the ViewModel.
/// A ViewModel-facing vocabulary type (consumed by `moveSelected`), so it lives in `Shared/` rather
/// than the AppKit-permitted `Canvas/` folder — it carries no AppKit value type. Named distinctly
/// from the Domain entity `CanvasItemMovement` (which it maps to) so a `grep CanvasItemMove` no
/// longer matches both layers.
struct CanvasDragMove: Sendable {
    let id: UUID
    let worldX: Double
    let worldY: Double
}
