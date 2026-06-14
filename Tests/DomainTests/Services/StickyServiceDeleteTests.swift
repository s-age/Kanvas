import XCTest
@testable import KanvasCore

/// `StickyService.deleting` cascade: deleting a sticky also drops any connector attached to it
/// (either end), so no connector is left with a dangling endpoint.
final class StickyServiceDeleteTests: XCTestCase {

    private var service: StickyService!

    override func setUp() {
        super.setUp()
        service = StickyService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testDeleting_cascadesConnectorsTouchingTheSticky() throws {
        let cardID = UUID()
        let target = Sticky(cardID: cardID, content: "a", position: .zero, sortIndex: 0)
        let other = Sticky(cardID: cardID, content: "b", position: .zero, sortIndex: 1)
        let bystander = Sticky(cardID: cardID, content: "c", position: .zero, sortIndex: 2)
        let attachedAsSource = Connector(cardID: cardID, sourceStickyID: target.id, sourceEdge: .right,
                                         targetStickyID: other.id, targetEdge: .left)
        let attachedAsTarget = Connector(cardID: cardID, sourceStickyID: other.id, sourceEdge: .right,
                                         targetStickyID: target.id, targetEdge: .left)
        let unrelated = Connector(cardID: cardID, sourceStickyID: other.id, sourceEdge: .top,
                                  targetStickyID: bystander.id, targetEdge: .bottom)

        var state = BoardState(board: Board(title: "B"), columns: [], cards: [],
                               stickies: [target, other, bystander])
        state.connectors = [attachedAsSource, attachedAsTarget, unrelated]

        let result = try service.deleting(id: target.id, from: state)

        XCTAssertFalse(result.stickies.contains { $0.id == target.id })
        XCTAssertEqual(result.connectors.map(\.id), [unrelated.id])
    }

    func testDeleting_unknownID_throwsNotFound() {
        let missingID = UUID()
        let state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])

        XCTAssertThrowsError(try service.deleting(id: missingID, from: state)) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Sticky", id: missingID))
        }
    }
}
