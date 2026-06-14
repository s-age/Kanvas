import XCTest
@testable import KanvasCore

/// `BoardResponseMapper` projects cards into the response in the order dictated by the board's
/// `cardSortPolicy` — the display path that surfaces the policy to Presentation.
final class BoardResponseMapperSortTests: XCTestCase {

    private let mapper = BoardResponseMapper()

    private func state(policy: CardSortPolicy) -> BoardState {
        let board = Board(title: "B")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let cards = [
            Card(columnID: column.id, title: "banana", createdAt: Date(timeIntervalSince1970: 100), sortIndex: 0),
            Card(columnID: column.id, title: "apple", createdAt: Date(timeIntervalSince1970: 300), sortIndex: 1),
            Card(columnID: column.id, title: "cherry", createdAt: Date(timeIntervalSince1970: 200), sortIndex: 2),
        ]
        var state = BoardState(board: board, columns: [column], cards: cards, stickies: [])
        state.settings.board = BoardTabSettings(cardSortPolicy: policy)
        return state
    }

    private func titles(_ response: BoardResponse) -> [String] {
        response.columns.first?.cards.map(\.title) ?? []
    }

    func testToBoardResponse_manual_usesSortIndexOrder() {
        let response = mapper.toBoardResponse(state(policy: .manual))

        XCTAssertEqual(titles(response), ["banana", "apple", "cherry"])
    }

    func testToBoardResponse_titleAscending_usesAlphabeticalOrder() {
        let response = mapper.toBoardResponse(state(policy: .titleAscending))

        XCTAssertEqual(titles(response), ["apple", "banana", "cherry"])
    }

    func testToBoardResponse_createdNewest_usesNewestFirst() {
        let response = mapper.toBoardResponse(state(policy: .createdNewest))

        XCTAssertEqual(titles(response), ["apple", "cherry", "banana"])
    }
}
