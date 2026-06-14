import Foundation

/// Orchestrates the durable Markdown autosave journal (ticket 44C9D3C2). A Shape-1 service that
/// holds the journal repository and runs the read/write itself — but, unlike the board services, it
/// does **not** touch `repository.mutate`: the journal is a separate substrate (per-card files,
/// no `flock`/undo), so there is no board state to reconcile. Imperative verbs matching the
/// repository.
final class MarkdownJournalService: MarkdownJournalServiceProtocol, Sendable {
    private let repository: any MarkdownJournalRepositoryProtocol

    init(repository: any MarkdownJournalRepositoryProtocol) {
        self.repository = repository
    }

    func record(cardID: UUID, content: String, at enqueuedAt: Date) async throws {
        try await repository.record(PendingMarkdownEdit(cardID: cardID, content: content, enqueuedAt: enqueuedAt))
    }

    func listAll() async throws -> [PendingMarkdownEdit] {
        try await repository.listAll()
    }

    func clear(cardID: UUID) async throws {
        try await repository.clear(cardID: cardID)
    }
}
