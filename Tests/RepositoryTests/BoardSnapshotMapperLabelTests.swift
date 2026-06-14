import XCTest
@testable import KanvasCore

/// `BoardSnapshotMapper` must round-trip the sticky-label registry and per-sticky `labelIDs`,
/// and must decode older snapshots (no `labels` / no `labelIDs`) into empty collections rather
/// than failing — the optional DTO fields are the backward-compat seam.
final class BoardSnapshotMapperLabelTests: XCTestCase {

    private func stickyDTO(id: UUID, cardID: UUID, labelIDs: [UUID]?) -> StickyDTO {
        StickyDTO(
            id: id, cardID: cardID, linkedCardID: nil, content: "a",
            positionX: 0, positionY: 0, width: 200, height: 150,
            textColorHex: nil, fontSize: nil, fillColorHex: nil, sortIndex: 0, labelIDs: labelIDs
        )
    }

    func testToEntities_decodesLabelRegistry() {
        let label = StickyLabelDTO(id: UUID(), name: "Urgent", colorHex: "FF0000")
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [], stickies: [], labels: [label]
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertEqual(state.labels, [StickyLabel(id: label.id, name: "Urgent", colorHex: "FF0000")])
    }

    func testToEntities_decodesStickyLabelIDs() {
        let cardID = UUID()
        let labelID = UUID()
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [stickyDTO(id: UUID(), cardID: cardID, labelIDs: [labelID])], labels: []
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertEqual(state.stickies.first?.labelIDs, [labelID])
    }

    func testToEntities_legacySnapshotWithoutLabels_decodesToEmpty() {
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [stickyDTO(id: UUID(), cardID: UUID(), labelIDs: nil)], labels: nil
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertEqual(state.labels, [])
    }

    func testToEntities_legacyStickyWithoutLabelIDs_decodesToEmpty() {
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [stickyDTO(id: UUID(), cardID: UUID(), labelIDs: nil)], labels: nil
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertEqual(state.stickies.first?.labelIDs, [])
    }

    func testToEntities_legacyStickyWithoutFillColor_decodesToNil() {
        // The `stickyDTO` helper sets fillColorHex nil — a snapshot predating the per-sticky fill.
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [stickyDTO(id: UUID(), cardID: UUID(), labelIDs: nil)], labels: nil
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertNil(state.stickies.first?.fillColorHex)
    }

    func testToEntities_legacyAutoStickyTextColor_migratesToConcreteDefault() {
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [StickyDTO(
                id: UUID(), cardID: UUID(), linkedCardID: nil, content: "a",
                positionX: 0, positionY: 0, width: 200, height: 150,
                textColorHex: "auto", fontSize: nil, fillColorHex: nil, sortIndex: 0, labelIDs: nil
            )], labels: nil
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertEqual(state.stickies.first?.style.colorHex, StickyTextStyle.defaultColorHex)
    }

    func testRoundTrip_preservesStickyFillColor() {
        let cardID = UUID()
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.stickies = [
            Sticky(cardID: cardID, content: "a", position: .zero, fillColorHex: "AB12CD", sortIndex: 0),
        ]

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.stickies.first?.fillColorHex, "AB12CD")
    }

    func testRoundTrip_preservesLabelsAndAssignments() {
        let cardID = UUID()
        let label = StickyLabel(name: "Urgent", colorHex: "FF0000")
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [], labels: [label])
        state.stickies = [
            Sticky(cardID: cardID, content: "a", position: .zero, sortIndex: 0, labelIDs: [label.id]),
        ]

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.stickies.first?.labelIDs, [label.id])
    }

    func testRoundTrip_preservesRegistry() {
        let label = StickyLabel(name: "Urgent", colorHex: "FF0000")
        let state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [], labels: [label])

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.labels, [label])
    }
}
