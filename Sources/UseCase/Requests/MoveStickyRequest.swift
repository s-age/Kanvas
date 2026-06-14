import Foundation

struct MoveStickyRequest: ValidatableRequest {
    let stickyID: UUID
    let positionX: Double
    let positionY: Double

    func validate() throws {
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
    }
}
