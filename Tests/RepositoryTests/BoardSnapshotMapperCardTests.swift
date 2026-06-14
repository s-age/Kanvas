import XCTest
@testable import KanvasCore

/// Pins the `Card.createdAt` persistence path: round-trips through the snapshot DTO and falls back
/// to `.distantPast` for legacy snapshots that predate the field (the DTO field is Optional).
final class BoardSnapshotMapperCardTests: XCTestCase {

    private func snapshot(cards: [CardDTO]) -> BoardSnapshotDTO {
        BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"),
            columns: [], cards: cards, stickies: []
        )
    }

    private func cardDTO(createdAt: Date?, prURL: String? = nil) -> CardDTO {
        CardDTO(
            id: UUID(),
            columnID: UUID(),
            title: "C",
            markdownContent: "",
            status: nil, // Legacy field — status is derived from the column now, not persisted.
            schedule: nil,
            labels: [],
            assignee: nil,
            prURL: prURL,
            completedAt: nil,
            createdAt: createdAt,
            sortIndex: 0
        )
    }

    func testToEntities_legacyCardWithoutCreatedAt_fallsBackToDistantPast() {
        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(snapshot(cards: [cardDTO(createdAt: nil)]))

        XCTAssertEqual(state.cards.first?.createdAt, .distantPast)
    }

    func testRoundTrip_preservesCreatedAt() {
        let created = Date(timeIntervalSince1970: 1_234_567)
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.cards = [Card(columnID: UUID(), title: "C", createdAt: created, sortIndex: 0)]

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.cards.first?.createdAt, created)
    }

    func testToEntities_legacyCardWithoutPRURL_decodesToNil() {
        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(snapshot(cards: [cardDTO(createdAt: nil)]))

        XCTAssertNil(state.cards.first?.prURL)
    }

    func testRoundTrip_preservesPRURL() {
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.cards = [Card(columnID: UUID(), title: "C", prURL: "https://github.com/o/r/pull/1", sortIndex: 0)]

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.cards.first?.prURL, "https://github.com/o/r/pull/1")
    }
}
