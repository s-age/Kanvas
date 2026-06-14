import Foundation

/// DataSource-style repository for the durable Markdown autosave journal. Bridges the Infrastructure
/// `MarkdownJournalStoreProtocol` to the `PendingMarkdownEdit` domain entity via
/// `MarkdownJournalMapper`; holds no business logic (ticket 44C9D3C2).
final class MarkdownJournalRepository: MarkdownJournalRepositoryProtocol, Sendable {
    private let store: any MarkdownJournalStoreProtocol

    init(store: any MarkdownJournalStoreProtocol) {
        self.store = store
    }

    func record(_ edit: PendingMarkdownEdit) async throws {
        try await store.save(MarkdownJournalMapper.toDTO(edit))
    }

    func listAll() async throws -> [PendingMarkdownEdit] {
        try await store.loadAll().map(MarkdownJournalMapper.toEntity)
    }

    func clear(cardID: UUID) async throws {
        try await store.delete(cardID: cardID)
    }
}
