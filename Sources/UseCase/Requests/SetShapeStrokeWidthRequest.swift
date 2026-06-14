import Foundation

struct SetShapeStrokeWidthRequest: ValidatableRequest {
    let shapeID: UUID
    let width: Double

    func validate() throws {
        try NumericBoundsValidation.validate(
            strokeWidth: width, in: CanvasShapeStyle.minStrokeWidth...CanvasShapeStyle.maxStrokeWidth
        )
    }
}
