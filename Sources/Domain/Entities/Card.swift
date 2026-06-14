import Foundation

struct Card: Sendable, Identifiable, Equatable {
    let id: UUID
    var columnID: Column.ID
    var title: String
    var markdownContent: String
    var schedule: CardSchedule?
    var labels: [CardLabel]
    var assignee: String?
    /// Pull-request URL linked to this card — set via MCP or the metadata editor so ticket ⇄ PR
    /// stay associated. Free-form `String?`; normalization (trim, blank → nil) lives at the UseCase
    /// boundary, mirroring `assignee`.
    var prURL: String?
    /// Stamped when the card enters the board's completion column, cleared when it leaves.
    /// Derived from card movement — not directly user-editable.
    var completedAt: Date?
    /// Creation timestamp — the ordering key for the `createdNewest` / `createdOldest`
    /// sort policies. Immutable; stamped by the creating service via its injected clock.
    /// The default is the deterministic `.distantPast`, **not** `Date()`, so omitting it never
    /// silently bypasses the injected clock — every real creation path passes the clock's value.
    let createdAt: Date
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        columnID: Column.ID,
        title: String,
        markdownContent: String = "",
        schedule: CardSchedule? = nil,
        labels: [CardLabel] = [],
        assignee: String? = nil,
        prURL: String? = nil,
        completedAt: Date? = nil,
        createdAt: Date = .distantPast,
        sortIndex: Int
    ) {
        self.id = id
        self.columnID = columnID
        self.title = title
        self.markdownContent = markdownContent
        self.schedule = schedule
        self.labels = labels
        self.assignee = assignee
        self.prURL = prURL
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }
}
