import Foundation

struct AddCardRequest: ValidatableRequest {
    let title: String
    let columnID: UUID
    /// Optional initial Markdown detail, seeded in the **same atomic mutation** as the card
    /// itself (one disk write, one undo entry). `nil` leaves the card's Markdown empty.
    var markdownContent: String?

    init(title: String, columnID: UUID, markdownContent: String? = nil) {
        self.title = title
        self.columnID = columnID
        self.markdownContent = markdownContent
    }

    func validate() throws {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }
        try ContentSizeValidation.validate(title: title)
        if let markdownContent {
            try ContentSizeValidation.validate(markdown: markdownContent)
        }
    }
}
