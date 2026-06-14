import Foundation

struct SetStickyFrameRequest: ValidatableRequest {
    let stickyID: UUID
    let width: Double
    let height: Double
    /// New centre. An anchored (corner-fixed) resize moves the centre as the size changes, so the
    /// full frame — size and position — is committed together as one atomic mutation (one undo
    /// entry). This is a full-frame set, not a pure resize.
    let positionX: Double
    let positionY: Double

    /// Only the position component is guarded here; `width`/`height` are clamped on the `StickySize`
    /// entity `init`, so a non-finite size is already neutralised downstream (ticket 4FD6D166).
    func validate() throws {
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
    }
}
