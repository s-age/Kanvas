import XCTest
@testable import KanvasCore

/// `RecordMarkdownJournalUseCaseImpl` — pins that it forwards the card/content and the request's
/// `enqueuedAt` (stamped by the autosave channel) unchanged to the journal service.
final class RecordMarkdownJournalUseCaseTests: XCTestCase {

    private final class MockJournalService: MarkdownJournalServiceProtocol, @unchecked Sendable {
        private(set) var recorded: [(cardID: UUID, content: String, at: Date)] = []
        func record(cardID: UUID, content: String, at enqueuedAt: Date) throws {
            recorded.append((cardID, content, enqueuedAt))
        }
        func listAll() throws -> [PendingMarkdownEdit] { [] }
        func clear(cardID: UUID) throws {}
    }

    func testExecute_forwardsContentAndEnqueuedAt() async throws {
        let service = MockJournalService()
        let sut = RecordMarkdownJournalUseCaseImpl(service: service)
        let cardID = UUID()
        let enqueuedAt = Date(timeIntervalSince1970: 42)

        try await sut.execute(
            RecordMarkdownJournalRequest(cardID: cardID, content: "notes", enqueuedAt: enqueuedAt)
        )

        XCTAssertEqual(service.recorded.count, 1)
        XCTAssertEqual(service.recorded.first?.cardID, cardID)
        XCTAssertEqual(service.recorded.first?.content, "notes")
        XCTAssertEqual(service.recorded.first?.at, enqueuedAt)
    }
}
