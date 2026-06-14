import Foundation

struct SetTextColorRequest: ValidatableRequest {
    let textID: UUID
    let colorHex: String

    // The text colour drives canvas drawing directly, so enforce the hex format here (mirrors the
    // shape stroke-colour flow) rather than relying on a downstream colour-parse fallback.
    func validate() throws {
        try LabelValidation.validate(colorHex: colorHex)
    }
}
