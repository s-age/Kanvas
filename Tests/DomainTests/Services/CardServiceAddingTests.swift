import XCTest
@testable import KanvasCore

/// `CardService.adding` must place a new card at the bottom of its column. Because
/// `moving` only recompacts the *target* column, a source column can be left with
/// gaps or with sortIndex values ≥ its card count, so the bottom slot is `max + 1`,
/// not `count`. These tests pin that so the placement cannot silently regress.
final class CardServiceAddingTests: XCTestCase {

    private static let fixedNow = Date(timeIntervalSince1970: 1_000_000)
    private var service: CardService!

    override func setUp() {
        super.setUp()
        service = CardService(repository: StubBoardRepository(), now: { Self.fixedNow })
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func order(_ state: BoardState, in columnID: UUID) -> [UUID] {
        state.cards
            .filter { $0.columnID == columnID }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.id)
    }

    func testAdding_toEmptyColumn_assignsSortIndexZero() {
        let board = Board(title: "Board")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let state = BoardState(board: board, columns: [column], cards: [], stickies: [])

        let result = service.adding(CardSeed(title: "New"), columnID: column.id, to: state)

        XCTAssertEqual(result.cards.first { $0.columnID == column.id }?.sortIndex, 0)
    }

    func testAdding_toColumnWithGappedSortIndices_placesCardLast() {
        let board = Board(title: "Board")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        // Simulates a column left with gaps after a card was moved out: indices 0, 2, 3.
        let existing = [0, 2, 3].map { Card(columnID: column.id, title: "c\($0)", sortIndex: $0) }
        let state = BoardState(board: board, columns: [column], cards: existing, stickies: [])

        let result = service.adding(CardSeed(title: "New"), columnID: column.id, to: state)

        let newCardID = result.cards.first { $0.title == "New" }?.id
        XCTAssertEqual(order(result, in: column.id).last, newCardID)
    }

    func testAdding_toColumnWithGappedSortIndices_assignsMaxPlusOne() {
        let board = Board(title: "Board")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let existing = [0, 2, 3].map { Card(columnID: column.id, title: "c\($0)", sortIndex: $0) }
        let state = BoardState(board: board, columns: [column], cards: existing, stickies: [])

        let result = service.adding(CardSeed(title: "New"), columnID: column.id, to: state)

        XCTAssertEqual(result.cards.first { $0.title == "New" }?.sortIndex, 4)
    }

    func testAdding_stampsCreatedAtFromInjectedClock() {
        let board = Board(title: "Board")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let state = BoardState(board: board, columns: [column], cards: [], stickies: [])

        let result = service.adding(CardSeed(title: "New"), columnID: column.id, to: state)

        XCTAssertEqual(result.cards.first { $0.title == "New" }?.createdAt, Self.fixedNow)
    }

    func testAdding_usesCallerSuppliedID() {
        let board = Board(title: "Board")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let state = BoardState(board: board, columns: [column], cards: [], stickies: [])
        let suppliedID = UUID()

        let result = service.adding(
            CardSeed(id: suppliedID, title: "New"), columnID: column.id, to: state
        )

        XCTAssertEqual(result.cards.first { $0.title == "New" }?.id, suppliedID)
    }

    func testAdding_seedsMarkdownContent() {
        let board = Board(title: "Board")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let state = BoardState(board: board, columns: [column], cards: [], stickies: [])

        let result = service.adding(
            CardSeed(title: "New", markdownContent: "# seeded"), columnID: column.id, to: state
        )

        XCTAssertEqual(result.cards.first { $0.title == "New" }?.markdownContent, "# seeded")
    }

    func testAdding_nilMarkdownContent_leavesMarkdownEmpty() {
        let board = Board(title: "Board")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let state = BoardState(board: board, columns: [column], cards: [], stickies: [])

        let result = service.adding(CardSeed(title: "New"), columnID: column.id, to: state)

        XCTAssertEqual(result.cards.first { $0.title == "New" }?.markdownContent, "")
    }

    // MARK: - newCardPosition

    func testAdding_newCardPositionTop_assignsMinMinusOne() {
        let board = Board(title: "Board")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let existing = [0, 1, 2].map { Card(columnID: column.id, title: "c\($0)", sortIndex: $0) }
        var state = BoardState(board: board, columns: [column], cards: existing, stickies: [])
        state.settings.board = BoardTabSettings(newCardPosition: .top)

        let result = service.adding(CardSeed(title: "New"), columnID: column.id, to: state)

        XCTAssertEqual(result.cards.first { $0.title == "New" }?.sortIndex, -1)
    }

    func testAdding_newCardPositionTop_placesCardFirst() {
        let board = Board(title: "Board")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let existing = [0, 1, 2].map { Card(columnID: column.id, title: "c\($0)", sortIndex: $0) }
        var state = BoardState(board: board, columns: [column], cards: existing, stickies: [])
        state.settings.board = BoardTabSettings(newCardPosition: .top)

        let result = service.adding(CardSeed(title: "New"), columnID: column.id, to: state)

        let newCardID = result.cards.first { $0.title == "New" }?.id
        XCTAssertEqual(order(result, in: column.id).first, newCardID)
    }
}
