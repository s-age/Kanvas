import Foundation

struct EditCardRequest: ValidatableRequest {
    let cardID: UUID
    var title: String?
    var markdownContent: String?
    var schedule: ScheduleInput??
    var labels: [CardLabel]?
    var assignee: String??
    var prURL: String??

    func validate() throws {
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { throw ValidationError.emptyTitle }
            try ContentSizeValidation.validate(title: title)
        }
        if let markdownContent {
            try ContentSizeValidation.validate(markdown: markdownContent)
        }
        // `assignee` / `prURL` are double-optional: outer `.some` means "set this field", inner is
        // the new value (`.none` clears it). Only a concrete string is model-supplied free text to cap.
        if case .some(.some(let assignee)) = assignee {
            try ContentSizeValidation.validate(assignee: assignee)
        }
        if case .some(.some(let prURL)) = prURL {
            try ContentSizeValidation.validate(url: prURL)
        }
        if case .some(.some(.period(let start, let end))) = schedule {
            guard end > start else { throw ValidationError.invalidDateRange }
        }
    }
}
