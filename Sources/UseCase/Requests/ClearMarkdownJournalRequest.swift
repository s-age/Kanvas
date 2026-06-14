import Foundation

/// Clears a card's durable autosave journal entry once its write lands (or the user discards it).
/// A no-op when absent, so there is nothing to validate (ticket 44C9D3C2).
struct ClearMarkdownJournalRequest: UseCaseRequest {
    let cardID: UUID
}
