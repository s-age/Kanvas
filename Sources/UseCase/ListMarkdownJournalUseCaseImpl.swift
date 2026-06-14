import Foundation

/// Lists every pending Markdown edit in the durable autosave journal so the board ViewModel can
/// re-enqueue them at startup (ticket 44C9D3C2). Request-less reader (standalone protocol), so it
/// conforms to `ListMarkdownJournalUseCase` directly rather than the `AsyncUseCase` base.
final class ListMarkdownJournalUseCaseImpl: ListMarkdownJournalUseCase, Sendable {
    private let service: any MarkdownJournalServiceProtocol

    init(service: any MarkdownJournalServiceProtocol) {
        self.service = service
    }

    func execute() async throws -> [PendingMarkdownEditResponse] {
        // Scans the journal directory + decodes each file — blocking I/O, offloaded inside the store
        // layer onto a dedicated serial queue (via `BlockingIOQueue`), so this `await` frees the
        // cooperative-pool thread (mirrors `SweepOrphanedImageAssetsUseCaseImpl`).
        return try await service.listAll().map(PendingMarkdownEditResponse.init(from:))
    }
}
