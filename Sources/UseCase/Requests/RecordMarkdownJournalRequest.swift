import Foundation

/// Records (or overwrites) a card's latest unsaved Markdown text in the durable autosave journal
/// (ticket 44C9D3C2). No invariant — `content` may be any string including empty (clearing notes is
/// a valid edit), so it is a plain `UseCaseRequest`, not validated. `enqueuedAt` is the edit's
/// "unsaved since …" timestamp, stamped by the autosave channel when the edit entered it (the
/// channel owns that moment), so the use case persists it rather than reading its own clock.
struct RecordMarkdownJournalRequest: UseCaseRequest {
    let cardID: UUID
    let content: String
    let enqueuedAt: Date
}
