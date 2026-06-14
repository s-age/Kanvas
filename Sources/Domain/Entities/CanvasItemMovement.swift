import Foundation

/// One canvas item's target position in a group move — an id paired with the world-space centre it
/// should move to. The canvas computes each member's destination (its original centre + the shared,
/// snapped drag delta); the batch of movements is applied in a single `mutate` so the whole gesture
/// is one undo step (ticket 4FF14DCF). The kind is resolved from `BoardState.canvasItemKind(of:)`
/// at apply time, so a movement only needs to carry the id + position.
struct CanvasItemMovement: Equatable, Sendable {
    let id: UUID
    let position: CanvasPosition
}
