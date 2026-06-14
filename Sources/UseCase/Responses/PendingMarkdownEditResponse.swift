import Foundation

/// A pending Markdown edit recovered from the durable autosave journal, exposed to Presentation
/// (ticket 44C9D3C2). The board ViewModel re-enqueues these into `MarkdownAutosaveQueue` at startup
/// so an edit lost to an app quit/crash — or stranded by a give-up — is retried.
struct PendingMarkdownEditResponse: Sendable, Equatable, Identifiable {
    var id: UUID { cardID }
    let cardID: UUID
    let content: String
    let enqueuedAt: Date

    init(from edit: PendingMarkdownEdit) {
        cardID = edit.cardID
        content = edit.content
        enqueuedAt = edit.enqueuedAt
    }
}
