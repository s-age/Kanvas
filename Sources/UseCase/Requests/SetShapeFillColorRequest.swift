import Foundation

struct SetShapeFillColorRequest: ValidatableRequest {
    let shapeID: UUID
    /// `nil` sets **no fill** (stroke-only); any value sets a literal fill colour.
    let colorHex: String?

    // `nil` (no fill) is valid; a present colour must be a 6-digit RGB hex.
    func validate() throws {
        if let colorHex {
            try LabelValidation.validate(colorHex: colorHex)
        }
    }
}
