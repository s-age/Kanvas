import Foundation

struct RenameColumnRequest: ValidatableRequest {
    let columnID: UUID
    let title: String

    func validate() throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }
        try ContentSizeValidation.validate(title: title)
    }
}
