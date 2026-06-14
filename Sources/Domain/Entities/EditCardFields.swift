import Foundation

/// Edit-fields bag for `CardService.editing`.
///
/// Each field is Optional so callers can express "leave unchanged" (nil) versus
/// "set to value" (.some(v)). `schedule` is doubly-optional:
/// - `nil`          → do not touch the field
/// - `.some(nil)`   → clear the schedule
/// - `.some(.some(v))` → set the schedule to v
struct EditCardFields: Sendable, Equatable {
    var title: String?
    var markdownContent: String?
    var schedule: CardSchedule??
    var labels: [CardLabel]?
    /// Same double-optional semantics as `schedule`:
    /// `nil` → leave unchanged, `.some(nil)` → clear, `.some(.some(v))` → set.
    var assignee: String??
    /// Same double-optional semantics as `assignee`:
    /// `nil` → leave unchanged, `.some(nil)` → clear, `.some(.some(v))` → set.
    var prURL: String??

    init(
        title: String? = nil,
        markdownContent: String? = nil,
        schedule: CardSchedule?? = nil,
        labels: [CardLabel]? = nil,
        assignee: String?? = nil,
        prURL: String?? = nil
    ) {
        self.title = title
        self.markdownContent = markdownContent
        self.schedule = schedule
        self.labels = labels
        self.assignee = assignee
        self.prURL = prURL
    }
}
