struct AddColumnRequest: ValidatableRequest {
    let title: String

    func validate() throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }
        try ContentSizeValidation.validate(title: title)
    }
}
