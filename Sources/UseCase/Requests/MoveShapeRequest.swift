import Foundation

struct MoveShapeRequest: ValidatableRequest {
    let shapeID: UUID
    let positionX: Double
    let positionY: Double

    func validate() throws {
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
    }
}
