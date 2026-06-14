import Foundation

struct MoveTextRequest: ValidatableRequest {
    let textID: UUID
    let positionX: Double
    let positionY: Double

    func validate() throws {
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
    }
}
