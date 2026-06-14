import Foundation

struct AddLabelRequest: ValidatableRequest {
    let name: String
    let colorHex: String

    func validate() throws {
        try LabelValidation.validate(name: name, colorHex: colorHex)
    }
}
