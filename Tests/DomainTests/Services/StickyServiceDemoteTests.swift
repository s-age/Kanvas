import XCTest
@testable import KanvasCore

/// `StickyService.demoting` turns a task sticky back into a free sticky: it clears `linkedCardID`
/// and removes the linked card together with that card's canvas children. Demoting a sticky that is
/// already free is a precondition violation (no link to detach), not a silent no-op.
final class StickyServiceDemoteTests: XCTestCase {

    private var service: StickyService!

    override func setUp() {
        super.setUp()
        service = StickyService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    /// A board carrying one task sticky on `hostCard` linked to `linkedCard`, plus one child sticky
    /// living on `linkedCard`'s own canvas (so the cascade has something to remove).
    private func taskStickyState() -> (BoardState, Sticky, Card) {
        let board = Board(title: "B")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let hostCard = Card(columnID: column.id, title: "host", sortIndex: 0)
        let linkedCard = Card(columnID: column.id, title: "linked", sortIndex: 1)
        var taskSticky = Sticky(cardID: hostCard.id, content: "task", position: .zero, sortIndex: 0)
        taskSticky.linkedCardID = linkedCard.id
        let child = Sticky(cardID: linkedCard.id, content: "child", position: .zero, sortIndex: 0)
        let state = BoardState(board: board, columns: [column], cards: [hostCard, linkedCard],
                               stickies: [taskSticky, child])
        return (state, taskSticky, linkedCard)
    }

    func testDemoting_taskSticky_clearsLinkedCardID() throws {
        let (state, taskSticky, _) = taskStickyState()

        let result = try service.demoting(id: taskSticky.id, in: state)

        XCTAssertNil(result.stickies.first { $0.id == taskSticky.id }?.linkedCardID)
    }

    func testDemoting_taskSticky_removesLinkedCardAndItsCanvasChildren() throws {
        let (state, taskSticky, linkedCard) = taskStickyState()

        let result = try service.demoting(id: taskSticky.id, in: state)

        XCTAssertFalse(result.cards.contains { $0.id == linkedCard.id })
        XCTAssertFalse(result.stickies.contains { $0.cardID == linkedCard.id })
    }

    func testDemoting_cascadesNestedLinkedCardSubtree() throws {
        // hostCard → linkedCard → grandchild. Demoting the task sticky deletes linkedCard *and*
        // grandchild (reached through a task sticky on linkedCard's own canvas), not one level.
        let board = Board(title: "B")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let hostCard = Card(columnID: column.id, title: "host", sortIndex: 0)
        let linkedCard = Card(columnID: column.id, title: "linked", sortIndex: 1)
        let grandchild = Card(columnID: column.id, title: "grandchild", sortIndex: 2)
        var taskSticky = Sticky(cardID: hostCard.id, content: "task", position: .zero, sortIndex: 0)
        taskSticky.linkedCardID = linkedCard.id
        var taskOnLinked = Sticky(cardID: linkedCard.id, content: "→grand", position: .zero, sortIndex: 0)
        taskOnLinked.linkedCardID = grandchild.id
        let leaf = Sticky(cardID: grandchild.id, content: "leaf", position: .zero, sortIndex: 0)
        let state = BoardState(board: board, columns: [column],
                               cards: [hostCard, linkedCard, grandchild],
                               stickies: [taskSticky, taskOnLinked, leaf])

        let result = try service.demoting(id: taskSticky.id, in: state)

        XCTAssertEqual(result.cards.map(\.id), [hostCard.id])
        XCTAssertEqual(result.stickies.map(\.id), [taskSticky.id])
    }

    func testDemoting_alreadyFreeSticky_throwsInconsistentState() {
        let board = Board(title: "B")
        let free = Sticky(cardID: UUID(), content: "free", position: .zero, sortIndex: 0)
        let state = BoardState(board: board, columns: [], cards: [], stickies: [free])

        XCTAssertThrowsError(try service.demoting(id: free.id, in: state)) { error in
            guard case .inconsistentState = error as? OperationError else {
                return XCTFail("expected inconsistentState, got \(error)")
            }
        }
    }

    func testDemoting_unknownID_throwsNotFound() {
        let state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        let missingID = UUID()

        XCTAssertThrowsError(try service.demoting(id: missingID, in: state)) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Sticky", id: missingID))
        }
    }
}
