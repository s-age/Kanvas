import Foundation

struct ResizeShapeRequest: ValidatableRequest {
    let shapeID: UUID
    let width: Double
    let height: Double
    /// New centre. An anchored (corner-fixed) resize moves the centre as the size changes, so
    /// size and position are committed together as one atomic mutation (one undo entry).
    let positionX: Double
    let positionY: Double
    /// Line only: which diagonal the segment runs along after an endpoint drag (`nil` for
    /// rectangle/ellipse, or to leave a line's orientation unchanged).
    let lineRising: Bool?

    /// Only the position component is guarded here; `width`/`height` are clamped on the `ShapeSize`
    /// entity `init`, so a non-finite size is already neutralised downstream (ticket 4FD6D166).
    func validate() throws {
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
    }
}
