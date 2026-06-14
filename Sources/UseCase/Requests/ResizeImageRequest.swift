import Foundation

struct ResizeImageRequest: ValidatableRequest {
    let imageID: UUID
    let width: Double
    let height: Double
    /// New centre. An anchored (corner-fixed) resize moves the centre as the size changes, so
    /// size and position are committed together as one atomic mutation (one undo entry).
    let positionX: Double
    let positionY: Double

    /// Only the position component is guarded here; `width`/`height` are clamped on the `ImageSize`
    /// entity `init`, so a non-finite size is already neutralised downstream (ticket 4FD6D166).
    func validate() throws {
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
    }
}
