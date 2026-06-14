import Foundation

struct EditLabelRequest: ValidatableRequest {
    let labelID: UUID
    let name: String
    let colorHex: String

    func validate() throws {
        try LabelValidation.validate(name: name, colorHex: colorHex)
    }
}
