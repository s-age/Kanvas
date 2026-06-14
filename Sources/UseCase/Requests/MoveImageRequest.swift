import Foundation

struct MoveImageRequest: ValidatableRequest {
    let imageID: UUID
    let positionX: Double
    let positionY: Double

    func validate() throws {
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
    }
}
