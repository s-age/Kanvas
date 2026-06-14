import XCTest
@testable import KanvasCore

/// `BoardSnapshotMapper.decode` must surface every transport recovery it applies — a discarded
/// malformed schedule, a dropped dangling connector, a connector field coerced from an unknown raw
/// value — so the Repository can log the latent write-back (`arch-repository.md` → "Latent
/// write-back in a whole-blob model"). A *legitimately absent* optional field is a default, not a
/// recovery, and must produce no note.
final class BoardSnapshotMapperRecoveryTests: XCTestCase {

    // MARK: - Schedule

    func testDecode_unknownScheduleKind_dropsScheduleAndRecords() {
        let card = cardDTO(schedule: CardScheduleDTO(kind: "weekly", date: nil, startDate: nil, endDate: nil))

        let result = BoardSnapshotMapper.decode(snapshot(cards: [card]))

        XCTAssertNil(result.state.cards.first?.schedule)
        XCTAssertEqual(result.recoveries.map(\.summary), ["card schedule dropped: unknown kind"])
    }

    func testDecode_deadlineMissingDate_dropsScheduleAndRecords() {
        let card = cardDTO(schedule: CardScheduleDTO(kind: "deadline", date: nil, startDate: nil, endDate: nil))

        let result = BoardSnapshotMapper.decode(snapshot(cards: [card]))

        XCTAssertNil(result.state.cards.first?.schedule)
        XCTAssertEqual(result.recoveries.map(\.summary), ["card schedule dropped: deadline missing date"])
    }

    func testDecode_periodMissingEndDate_dropsScheduleAndRecords() {
        let card = cardDTO(schedule: CardScheduleDTO(kind: "period", date: nil,
                                                     startDate: Date(timeIntervalSince1970: 1), endDate: nil))

        let result = BoardSnapshotMapper.decode(snapshot(cards: [card]))

        XCTAssertNil(result.state.cards.first?.schedule)
        XCTAssertEqual(result.recoveries.map(\.summary), ["card schedule dropped: period missing start/end"])
    }

    func testDecode_recordedScheduleDrop_carriesCardIDAndRawKind() {
        let cardID = UUID()
        let card = cardDTO(id: cardID, schedule: CardScheduleDTO(kind: "weekly", date: nil,
                                                                 startDate: nil, endDate: nil))

        let detail = BoardSnapshotMapper.decode(snapshot(cards: [card])).recoveries.first?.detail

        XCTAssertEqual(detail, "card=\(cardID) kind=weekly")
    }

    func testDecode_absentSchedule_recordsNoRecovery() {
        let result = BoardSnapshotMapper.decode(snapshot(cards: [cardDTO(schedule: nil)]))

        XCTAssertTrue(result.recoveries.isEmpty)
    }

    func testDecode_validDeadline_decodesAndRecordsNoRecovery() {
        let date = Date(timeIntervalSince1970: 1_000)
        let card = cardDTO(schedule: CardScheduleDTO(kind: "deadline", date: date,
                                                     startDate: nil, endDate: nil))

        let result = BoardSnapshotMapper.decode(snapshot(cards: [card]))

        XCTAssertEqual(result.state.cards.first?.schedule, .deadline(date))
        XCTAssertTrue(result.recoveries.isEmpty)
    }

    // MARK: - Connector

    func testDecode_connectorWithMissingEndpoint_dropsAndRecords() {
        let cardID = UUID()
        let present = UUID()
        let dto = snapshot(stickies: [stickyDTO(id: present, cardID: cardID)], connectors: [
            connectorDTO(cardID: cardID, source: present, target: UUID()) // target absent
        ])

        let result = BoardSnapshotMapper.decode(dto)

        XCTAssertTrue(result.state.connectors.isEmpty)
        XCTAssertEqual(result.recoveries.map(\.summary), ["connector dropped: endpoint sticky absent"])
    }

    func testDecode_connectorUnknownCap_coercesToArrowAndRecords() {
        let cardID = UUID()
        let source = UUID()
        let target = UUID()
        let dto = snapshot(
            stickies: [stickyDTO(id: source, cardID: cardID), stickyDTO(id: target, cardID: cardID)],
            connectors: [connectorDTO(cardID: cardID, source: source, target: target, cap: "spiral")]
        )

        let result = BoardSnapshotMapper.decode(dto)

        XCTAssertEqual(result.state.connectors.first?.style.cap, .arrow)
        XCTAssertEqual(result.recoveries.map(\.summary), ["connector cap coerced to default"])
    }

    func testDecode_connectorUnknownSourceEdge_coercesToRightAndRecords() {
        let cardID = UUID()
        let source = UUID()
        let target = UUID()
        let dto = snapshot(
            stickies: [stickyDTO(id: source, cardID: cardID), stickyDTO(id: target, cardID: cardID)],
            connectors: [connectorDTO(cardID: cardID, source: source, target: target, sourceEdge: "north")]
        )

        let result = BoardSnapshotMapper.decode(dto)

        XCTAssertEqual(result.state.connectors.first?.sourceEdge, .right)
        XCTAssertEqual(result.recoveries.map(\.summary), ["connector sourceEdge coerced to default"])
    }

    func testDecode_recordedCapCoercion_carriesRawAndFallback() {
        let cardID = UUID()
        let source = UUID()
        let target = UUID()
        let connectorID = UUID()
        let dto = snapshot(
            stickies: [stickyDTO(id: source, cardID: cardID), stickyDTO(id: target, cardID: cardID)],
            connectors: [connectorDTO(id: connectorID, cardID: cardID, source: source, target: target,
                                      cap: "spiral")]
        )

        let detail = BoardSnapshotMapper.decode(dto).recoveries.first?.detail

        XCTAssertEqual(detail, "connector=\(connectorID) raw=spiral fallback=arrow")
    }

    func testDecode_connectorAbsentCapAndRouting_recordsNoRecovery() {
        let cardID = UUID()
        let source = UUID()
        let target = UUID()
        let dto = snapshot(
            stickies: [stickyDTO(id: source, cardID: cardID), stickyDTO(id: target, cardID: cardID)],
            connectors: [connectorDTO(cardID: cardID, source: source, target: target,
                                      cap: nil, routing: nil)]
        )

        XCTAssertTrue(BoardSnapshotMapper.decode(dto).recoveries.isEmpty)
    }

    func testDecode_cleanSnapshot_recordsNoRecovery() {
        XCTAssertTrue(BoardSnapshotMapper.decode(snapshot()).recoveries.isEmpty)
    }

    // MARK: - Fixtures

    private func snapshot(cards: [CardDTO] = [], stickies: [StickyDTO] = [],
                          connectors: [ConnectorDTO] = []) -> BoardSnapshotDTO {
        BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"),
            columns: [], cards: cards, stickies: stickies,
            shapes: nil, images: nil, connectors: connectors, labels: nil
        )
    }

    private func cardDTO(id: UUID = UUID(), schedule: CardScheduleDTO?) -> CardDTO {
        CardDTO(
            id: id, columnID: UUID(), title: "C", markdownContent: "",
            status: nil, schedule: schedule, labels: [],
            assignee: nil, prURL: nil, completedAt: nil, createdAt: nil, sortIndex: 0
        )
    }

    private func stickyDTO(id: UUID, cardID: UUID) -> StickyDTO {
        StickyDTO(id: id, cardID: cardID, linkedCardID: nil, content: "x",
                  positionX: 0, positionY: 0, width: 100, height: 80,
                  textColorHex: nil, fontSize: nil, fillColorHex: nil, sortIndex: nil, labelIDs: nil)
    }

    private func connectorDTO(id: UUID = UUID(), cardID: UUID, source: UUID, target: UUID,
                              sourceEdge: String = "right", cap: String? = nil,
                              routing: String? = nil) -> ConnectorDTO {
        ConnectorDTO(
            id: id, cardID: cardID,
            sourceStickyID: source, sourceEdge: sourceEdge,
            targetStickyID: target, targetEdge: "left",
            cap: cap, routing: routing, strokeColorHex: nil, strokeWidth: nil
        )
    }
}
