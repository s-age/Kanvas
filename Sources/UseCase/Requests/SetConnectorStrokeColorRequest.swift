import Foundation

struct SetConnectorStrokeColorRequest: ValidatableRequest {
    let connectorID: UUID
    /// New explicit stroke colour ("RRGGBB"), or `nil` to clear back to unset (adaptive at draw time).
    let colorHex: String?

    // The stroke colour drives canvas drawing directly, so enforce the hex format here (mirrors the
    // shape flow) rather than relying on a downstream colour-parse fallback. A nil clear has no hex
    // to validate.
    func validate() throws {
        if let colorHex {
            try LabelValidation.validate(colorHex: colorHex)
        }
    }
}
