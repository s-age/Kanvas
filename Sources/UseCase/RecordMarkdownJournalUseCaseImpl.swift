import Foundation

/// Records a card's latest unsaved Markdown text in the durable autosave journal (ticket 44C9D3C2).
/// `enqueuedAt` is carried on the request — stamped by the autosave channel when the edit entered it
/// (the channel owns the "unsaved since …" moment), so the use case persists it rather than reading
/// its own clock.
final class RecordMarkdownJournalUseCaseImpl: AsyncUseCase, Sendable {
    private let service: any MarkdownJournalServiceProtocol

    init(service: any MarkdownJournalServiceProtocol) {
        self.service = service
    }

    func execute(_ request: RecordMarkdownJournalRequest) async throws {
        // A single small atomic file write. That blocking I/O is offloaded inside the store layer onto
        // a dedicated serial queue (via `BlockingIOQueue`), so this `await` frees the cooperative-pool
        // thread — a call from the main-actor autosave drain never stalls the UI.
        try await service.record(cardID: request.cardID, content: request.content, at: request.enqueuedAt)
    }
}
