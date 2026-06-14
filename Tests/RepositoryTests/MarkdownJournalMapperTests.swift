import XCTest
@testable import KanvasCore

/// `MarkdownJournalMapper` — pins the DTO ⇄ `PendingMarkdownEdit` round-trip so the encode/decode
/// pair cannot drift (ticket 44C9D3C2).
final class MarkdownJournalMapperTests: XCTestCase {

    func testRoundTrip_preservesAllFields() {
        let edit = PendingMarkdownEdit(
            cardID: UUID(), content: "# notes", enqueuedAt: Date(timeIntervalSince1970: 123)
        )

        let roundTripped = MarkdownJournalMapper.toEntity(MarkdownJournalMapper.toDTO(edit))

        XCTAssertEqual(roundTripped, edit)
    }
}
