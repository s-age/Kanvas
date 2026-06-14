import Foundation

/// Clears a card's durable autosave journal entry — called when its write lands or the user
/// discards the stranded edit (ticket 44C9D3C2).
final class ClearMarkdownJournalUseCaseImpl: AsyncUseCase, Sendable {
    private let service: any MarkdownJournalServiceProtocol

    init(service: any MarkdownJournalServiceProtocol) {
        self.service = service
    }

    func execute(_ request: ClearMarkdownJournalRequest) async throws {
        // A single small file removal. That blocking I/O is offloaded inside the store layer onto a
        // dedicated serial queue (via `BlockingIOQueue`), so this `await` frees the cooperative-pool
        // thread rather than parking it.
        try await service.clear(cardID: request.cardID)
    }
}
