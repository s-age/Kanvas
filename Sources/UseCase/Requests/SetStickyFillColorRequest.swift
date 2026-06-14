import Foundation

struct SetStickyFillColorRequest: ValidatableRequest {
    let stickyID: UUID
    /// New background fill ("RRGGBB"), or `nil` to clear back to the board's free/task default.
    let fillColorHex: String?

    // `nil` (clear to default) is valid; a present colour must be a 6-digit RGB hex.
    func validate() throws {
        if let fillColorHex {
            try LabelValidation.validate(colorHex: fillColorHex)
        }
    }
}
