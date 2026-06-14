import Foundation

/// A Markdown edit that has been handed to the autosave channel but not yet confirmed persisted
/// to the board store — the durable journal's unit (ticket 44C9D3C2). The autosave queue
/// (`MarkdownAutosaveQueue`, Presentation) writes one of these to disk *before* attempting the
/// real board write and deletes it on success, so a pending edit survives an app quit/crash or a
/// give-up after repeated failures. On the next launch the leftover entries are restored and the
/// writes retried.
///
/// Keyed by `cardID` (which is also `id`) so the journal is naturally coalescing — only the latest
/// unsaved text per card is ever retained. `enqueuedAt` records when the edit entered the channel,
/// used to surface "unsaved since …" in the editor's manual retry/discard banner.
struct PendingMarkdownEdit: Identifiable, Equatable, Sendable {
    var id: UUID { cardID }
    let cardID: UUID
    let content: String
    let enqueuedAt: Date

    init(cardID: UUID, content: String, enqueuedAt: Date) {
        self.cardID = cardID
        self.content = content
        self.enqueuedAt = enqueuedAt
    }
}
