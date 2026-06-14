import XCTest
@testable import KanvasCore

/// `BoardState.resolvedCompletedAt` is the single source of the `completedAt` invariant. When the
/// `autoCompleteOnMove` setting is on it stamps/clears based on the completion column; when off it
/// leaves the timestamp untouched so the user can manage completion manually.
final class BoardStateCompletedAtTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000)

    private func makeState(completionColumn: Bool, autoComplete: Bool) -> (BoardState, Column.ID) {
        let board = Board(title: "B")
        let column = Column(boardID: board.id, title: "Done", sortIndex: 0, isCompletionColumn: completionColumn)
        var state = BoardState(board: board, columns: [column], cards: [], stickies: [])
        state.settings.board = BoardTabSettings(autoCompleteOnMove: autoComplete)
        return (state, column.id)
    }

    // MARK: - auto-complete ON (default)

    func testResolved_autoCompleteOn_completionColumn_stampsNow() {
        let (state, columnID) = makeState(completionColumn: true, autoComplete: true)

        let result = state.resolvedCompletedAt(columnID: columnID, existing: nil, now: now)

        XCTAssertEqual(result, now)
    }

    func testResolved_autoCompleteOn_nonCompletionColumn_clearsTimestamp() {
        let (state, columnID) = makeState(completionColumn: false, autoComplete: true)

        let result = state.resolvedCompletedAt(columnID: columnID, existing: now, now: now)

        XCTAssertNil(result)
    }

    // MARK: - auto-complete OFF

    func testResolved_autoCompleteOff_completionColumn_doesNotStamp() {
        let (state, columnID) = makeState(completionColumn: true, autoComplete: false)

        let result = state.resolvedCompletedAt(columnID: columnID, existing: nil, now: now)

        XCTAssertNil(result)
    }

    func testResolved_autoCompleteOff_preservesExistingTimestamp() {
        let (state, columnID) = makeState(completionColumn: false, autoComplete: false)

        let result = state.resolvedCompletedAt(columnID: columnID, existing: now, now: now)

        XCTAssertEqual(result, now)
    }
}
