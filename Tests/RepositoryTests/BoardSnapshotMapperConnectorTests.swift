import XCTest
@testable import KanvasCore

/// `BoardSnapshotMapper` must round-trip connectors (endpoints + edges + cap/routing/stroke) and
/// must decode connector-less snapshots into an empty collection.
final class BoardSnapshotMapperConnectorTests: XCTestCase {

    /// A state holding `connector` plus the two endpoint stickies it references, so load-time
    /// healing (which drops connectors with missing endpoints) keeps it.
    private func state(with connector: Connector) -> BoardState {
        let source = Sticky(id: connector.sourceStickyID, cardID: connector.cardID,
                            content: "s", position: .zero, sortIndex: 0)
        let target = Sticky(id: connector.targetStickyID, cardID: connector.cardID,
                            content: "t", position: .zero, sortIndex: 1)
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [],
                               stickies: [source, target])
        state.connectors = [connector]
        return state
    }

    private func connector(style: ConnectorStyle) -> Connector {
        Connector(cardID: UUID(), sourceStickyID: UUID(), sourceEdge: .top,
                  targetStickyID: UUID(), targetEdge: .left, style: style)
    }

    func testRoundTrip_preservesEdges() {
        let original = connector(style: .default)
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: original))
        )

        XCTAssertEqual(restored.connectors.first?.sourceEdge, .top)
        XCTAssertEqual(restored.connectors.first?.targetEdge, .left)
        XCTAssertEqual(restored.connectors.first?.sourceStickyID, original.sourceStickyID)
        XCTAssertEqual(restored.connectors.first?.targetStickyID, original.targetStickyID)
    }

    func testRoundTrip_preservesStyle() {
        let style = ConnectorStyle(cap: .line, routing: .curve, strokeColorHex: "445566", strokeWidth: 6)
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: connector(style: style)))
        )

        let restoredStyle = restored.connectors.first?.style
        XCTAssertEqual(restoredStyle?.cap, .line)
        XCTAssertEqual(restoredStyle?.routing, .curve)
        XCTAssertEqual(restoredStyle?.strokeColorHex, "445566")
        XCTAssertEqual(restoredStyle?.strokeWidth, 6)
    }

    func testRoundTrip_preservesWaypointOffset() {
        var original = connector(style: .default)
        original.waypointOffset = CanvasOffset(dx: 12, dy: -34)
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: original))
        )

        XCTAssertEqual(restored.connectors.first?.waypointOffset, CanvasOffset(dx: 12, dy: -34))
    }

    func testRoundTrip_noWaypoint_staysNil() {
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: connector(style: .default)))
        )

        XCTAssertNil(restored.connectors.first?.waypointOffset)
    }

    func testToEntities_legacySnapshotMissingWaypointFields_decodesToNil() {
        let cardID = UUID()
        let sourceID = UUID()
        let targetID = UUID()
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [stickyDTO(id: sourceID, cardID: cardID), stickyDTO(id: targetID, cardID: cardID)],
            shapes: nil,
            connectors: [ConnectorDTO(
                id: UUID(), cardID: cardID,
                sourceStickyID: sourceID, sourceEdge: "right",
                targetStickyID: targetID, targetEdge: "left",
                cap: nil, routing: "elbow", strokeColorHex: nil, strokeWidth: nil
            )],
            labels: nil
        )

        XCTAssertNil(BoardSnapshotMapper.decodeIgnoringRecoveries(dto).connectors.first?.waypointOffset)
    }

    func testToEntities_halfWrittenWaypointPair_decodesToNil() {
        // Only one axis present — incoherent (the all-or-nothing contract), so it is no waypoint.
        let cardID = UUID()
        let sourceID = UUID()
        let targetID = UUID()
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [stickyDTO(id: sourceID, cardID: cardID), stickyDTO(id: targetID, cardID: cardID)],
            shapes: nil,
            connectors: [ConnectorDTO(
                id: UUID(), cardID: cardID,
                sourceStickyID: sourceID, sourceEdge: "right",
                targetStickyID: targetID, targetEdge: "left",
                cap: nil, routing: "curve", strokeColorHex: nil, strokeWidth: nil,
                waypointOffsetX: 5, waypointOffsetY: nil
            )],
            labels: nil
        )

        XCTAssertNil(BoardSnapshotMapper.decodeIgnoringRecoveries(dto).connectors.first?.waypointOffset)
    }

    func testToEntities_legacySnapshotWithoutConnectors_decodesToEmpty() {
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [], shapes: nil, connectors: nil, labels: nil
        )

        XCTAssertTrue(BoardSnapshotMapper.decodeIgnoringRecoveries(dto).connectors.isEmpty)
    }

    func testToEntities_connectorWithMissingStyleFields_decodesToDefaultsAndUnsetStroke() {
        let cardID = UUID()
        let sourceID = UUID()
        let targetID = UUID()
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [stickyDTO(id: sourceID, cardID: cardID), stickyDTO(id: targetID, cardID: cardID)],
            shapes: nil,
            connectors: [ConnectorDTO(
                id: UUID(), cardID: cardID,
                sourceStickyID: sourceID, sourceEdge: "right",
                targetStickyID: targetID, targetEdge: "left",
                cap: nil, routing: nil, strokeColorHex: nil, strokeWidth: nil
            )],
            labels: nil
        )

        let style = BoardSnapshotMapper.decodeIgnoringRecoveries(dto).connectors.first?.style
        XCTAssertEqual(style?.cap, .arrow)
        XCTAssertEqual(style?.routing, .straight)
        // An absent stroke decodes to unset (nil) — preserved verbatim, not coalesced to a sentinel —
        // so a snapshot predating the field renders adaptively rather than as a fixed `#000`.
        XCTAssertNil(style?.strokeColorHex)
        XCTAssertEqual(style?.strokeWidth, ConnectorStyle.defaultStrokeWidth)
    }

    /// Load-time healing: a connector whose endpoint sticky is absent is dropped, so unreachable
    /// garbage cannot accumulate in the snapshot.
    func testToEntities_connectorWithMissingEndpointSticky_isDropped() {
        let cardID = UUID()
        let presentSticky = UUID()
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [stickyDTO(id: presentSticky, cardID: cardID)],
            shapes: nil,
            connectors: [ConnectorDTO(
                id: UUID(), cardID: cardID,
                sourceStickyID: presentSticky, sourceEdge: "right",
                targetStickyID: UUID(), targetEdge: "left",  // target sticky does not exist
                cap: nil, routing: nil, strokeColorHex: nil, strokeWidth: nil
            )],
            labels: nil
        )

        XCTAssertTrue(BoardSnapshotMapper.decodeIgnoringRecoveries(dto).connectors.isEmpty)
    }

    private func stickyDTO(id: UUID, cardID: UUID) -> StickyDTO {
        StickyDTO(id: id, cardID: cardID, linkedCardID: nil, content: "x",
                  positionX: 0, positionY: 0, width: 100, height: 80,
                  textColorHex: nil, fontSize: nil, fillColorHex: nil, sortIndex: nil, labelIDs: nil)
    }
}
