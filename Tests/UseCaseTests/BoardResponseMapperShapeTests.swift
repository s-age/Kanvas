import XCTest
@testable import KanvasCore

/// `BoardResponseMapper.toCardDetailResponse` maps domain `CanvasShape` to `ShapeResponse`:
/// the open `kind` string passes through verbatim and `topology` is mirrored to the Response enum.
final class BoardResponseMapperShapeTests: XCTestCase {

    private let mapper = BoardResponseMapper()

    private func cardID() -> UUID { UUID() }

    /// Builds a minimal `BoardState` with a single card and one shape attached to it.
    private func state(cardID: UUID, kind: String, topology: ShapeTopology) -> BoardState {
        let board = Board(title: "B")
        let column = Column(boardID: board.id, title: "Col", sortIndex: 0)
        let card = Card(id: cardID, columnID: column.id, title: "C", sortIndex: 0)
        var s = BoardState(board: board, columns: [column], cards: [card], stickies: [])
        s.shapes = [CanvasShape(cardID: cardID, kind: kind, topology: topology,
                                position: .zero, sortIndex: 0)]
        return s
    }

    // MARK: - kind pass-through

    func testShapeResponse_openKindPassesThroughVerbatim() {
        let cid = cardID()
        let response = mapper.toCardDetailResponse(cardID: cid,
                                                   from: state(cardID: cid, kind: "triangle", topology: .box))

        XCTAssertEqual(response?.shapes.first?.kind, "triangle")
    }

    // MARK: - topology mapping

    func testShapeResponse_boxTopology_mapsToBoxResponse() {
        let cid = cardID()
        let response = mapper.toCardDetailResponse(cardID: cid,
                                                   from: state(cardID: cid, kind: "triangle", topology: .box))

        XCTAssertEqual(response?.shapes.first?.topology, .box)
    }

    func testShapeResponse_segmentTopology_mapsToSegmentResponse() {
        let cid = cardID()
        let response = mapper.toCardDetailResponse(cardID: cid,
                                                   from: state(cardID: cid, kind: "line", topology: .segment))

        XCTAssertEqual(response?.shapes.first?.topology, .segment)
    }
}
