import Foundation

struct SetShapeStrokeColorRequest: ValidatableRequest {
    let shapeID: UUID
    let colorHex: String

    // The stroke colour drives canvas drawing directly, so enforce the hex format here (mirrors the
    // label flow) rather than relying on a downstream colour-parse fallback.
    func validate() throws {
        try LabelValidation.validate(colorHex: colorHex)
    }
}
