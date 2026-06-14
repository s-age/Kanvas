import Foundation

/// The persisted shape of one pending Markdown edit in the durable autosave journal
/// (`Kanvas/markdown-journal/<cardID>.json`). One file per card, so the journal is naturally
/// coalescing — a newer edit overwrites the card's file. Mapped to `PendingMarkdownEdit` by
/// `MarkdownJournalMapper` (Repository); this layer treats it as opaque transport.
struct MarkdownJournalEntryDTO: Sendable, Codable {
    var cardID: UUID
    var content: String
    var enqueuedAt: Date
}
