import XCTest
@testable import KanvasCore

/// `BoardState.status(forColumn:)` is the single source of a card's status: it is derived from the
/// column the card sits in. Completion column → `.done`, leftmost column → `.todo`, every column in
/// between → `.inProgress`. An unknown column id falls back to `.todo`.
final class BoardStateStatusTests: XCTestCase {

    /// A standard three-column board (To Do / In Progress / Done) with Done flagged as completion.
    private func makeState() -> (BoardState, todo: Column.ID, doing: Column.ID, done: Column.ID) {
        let board = Board(title: "B")
        let todo = Column(boardID: board.id, title: "To Do", sortIndex: 0)
        let doing = Column(boardID: board.id, title: "In Progress", sortIndex: 1)
        let done = Column(boardID: board.id, title: "Done", sortIndex: 2, isCompletionColumn: true)
        let state = BoardState(board: board, columns: [todo, doing, done], cards: [], stickies: [])
        return (state, todo.id, doing.id, done.id)
    }

    func testStatus_completionColumn_isDone() {
        let (state, _, _, done) = makeState()

        XCTAssertEqual(state.status(forColumn: done), .done)
    }

    func testStatus_leftmostColumn_isTodo() {
        let (state, todo, _, _) = makeState()

        XCTAssertEqual(state.status(forColumn: todo), .todo)
    }

    func testStatus_middleColumn_isInProgress() {
        let (state, _, doing, _) = makeState()

        XCTAssertEqual(state.status(forColumn: doing), .inProgress)
    }

    func testStatus_unknownColumn_fallsBackToTodo() {
        let (state, _, _, _) = makeState()

        XCTAssertEqual(state.status(forColumn: UUID()), .todo)
    }

    // MARK: - columnTitle(forColumn:)

    func testColumnTitle_returnsColumnTitle() {
        let (state, _, doing, _) = makeState()

        XCTAssertEqual(state.columnTitle(forColumn: doing), "In Progress")
    }

    func testColumnTitle_unknownColumn_isEmpty() {
        let (state, _, _, _) = makeState()

        XCTAssertEqual(state.columnTitle(forColumn: UUID()), "")
    }

    /// The leftmost column is decided by `sortIndex`, not array order — a non-completion column with
    /// the lowest `sortIndex` reads `.todo` even when it is not first in the array.
    func testStatus_leftmostBySortIndexNotArrayOrder() {
        let board = Board(title: "B")
        let later = Column(boardID: board.id, title: "In Progress", sortIndex: 5)
        let earliest = Column(boardID: board.id, title: "To Do", sortIndex: 1)
        let state = BoardState(board: board, columns: [later, earliest], cards: [], stickies: [])

        XCTAssertEqual(state.status(forColumn: earliest.id), .todo)
        XCTAssertEqual(state.status(forColumn: later.id), .inProgress)
    }
}
