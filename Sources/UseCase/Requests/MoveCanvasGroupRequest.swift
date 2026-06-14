import Foundation

/// Moves a multi-selection of canvas items in one batch (one undo entry — ticket 4FF14DCF). Each
/// `Movement` carries an item id and its new world-space centre, in primitives so Presentation can
/// build the request without naming a Domain type; the use case maps them to `CanvasItemMovement`.
struct MoveCanvasGroupRequest: ValidatableRequest {
    let movements: [Movement]
    /// The card whose canvas the moved items belong to, so the mutation can return that card's
    /// refreshed detail (skipping a second disk read — ticket 1DCBF9C9).
    let cardID: UUID

    /// One item's target: its id and new world-space centre.
    struct Movement: Sendable {
        let id: UUID
        let positionX: Double
        let positionY: Double
    }

    /// Every movement's centre must be finite; a single `NaN`/`Inf` would poison the whole batch
    /// (it lands as one undo entry), so it is rejected before any write (ticket 4FD6D166).
    func validate() throws {
        try NumericBoundsValidation.validate(
            finiteCoordinates: movements.flatMap { [$0.positionX, $0.positionY] }
        )
    }
}
