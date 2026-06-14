import XCTest
@testable import KanvasCore

/// Unit tests for the pure card-search matcher `CardQuery.matchingCardIDs(in:query:)` (ticket
/// 59B10FBA): substring across title / Markdown body / sticky text / card UUID, case-insensitive,
/// OR-combined, blank-query = no-filter.
final class CardQueryTests: XCTestCase {

    private var board: Board!
    private var column: Column!

    override func setUp() {
        super.setUp()
        board = Board(title: "B")
        column = Column(boardID: board.id, title: "Todo", sortIndex: 0)
    }

    override func tearDown() {
        board = nil
        column = nil
        super.tearDown()
    }

    private func card(title: String = "Card", markdown: String = "") -> Card {
        Card(columnID: column.id, title: title, markdownContent: markdown, sortIndex: 0)
    }

    private func state(cards: [Card], stickies: [Sticky] = []) -> BoardState {
        BoardState(board: board, columns: [column], cards: cards, stickies: stickies)
    }

    // MARK: - Title match

    func testMatchingCardIDs_titleSubstring_matches() {
        let target = card(title: "Buy milk")
        let other = card(title: "Walk dog")
        let result = CardQuery.matchingCardIDs(in: state(cards: [target, other]), query: "milk")
        XCTAssertEqual(result, [target.id])
    }

    // MARK: - Markdown body match

    func testMatchingCardIDs_markdownBodySubstring_matches() {
        let target = card(title: "A", markdown: "remember the **secret** plan")
        let other = card(title: "B", markdown: "nothing here")
        let result = CardQuery.matchingCardIDs(in: state(cards: [target, other]), query: "secret")
        XCTAssertEqual(result, [target.id])
    }

    // MARK: - Sticky text match

    func testMatchingCardIDs_stickyContentSubstring_matches() {
        let target = card(title: "A")
        let other = card(title: "B")
        let sticky = Sticky(cardID: target.id, content: "needle in here",
                            position: CanvasPosition(x: 0, y: 0), sortIndex: 0)
        let result = CardQuery.matchingCardIDs(
            in: state(cards: [target, other], stickies: [sticky]), query: "needle")
        XCTAssertEqual(result, [target.id])
    }

    func testMatchingCardIDs_multipleStickiesOnOneCard_matchesViaSecond() {
        let target = card(title: "A")
        let first = Sticky(cardID: target.id, content: "alpha",
                           position: CanvasPosition(x: 0, y: 0), sortIndex: 0)
        let second = Sticky(cardID: target.id, content: "omega",
                            position: CanvasPosition(x: 1, y: 1), sortIndex: 1)
        let result = CardQuery.matchingCardIDs(
            in: state(cards: [target], stickies: [first, second]), query: "omega")
        XCTAssertEqual(result, [target.id])
    }

    // MARK: - UUID match

    func testMatchingCardIDs_uuidSubstring_matches() {
        let target = card(title: "A")
        let other = card(title: "B")
        let fragment = String(target.id.uuidString.prefix(8))
        let result = CardQuery.matchingCardIDs(in: state(cards: [target, other]), query: fragment)
        XCTAssertEqual(result, [target.id])
    }

    func testMatchingCardIDs_uuidSubstringLowercased_matches() {
        let target = card(title: "A")
        let fragment = String(target.id.uuidString.prefix(8)).lowercased()
        let result = CardQuery.matchingCardIDs(in: state(cards: [target]), query: fragment)
        XCTAssertEqual(result, [target.id])
    }

    // MARK: - Case-insensitivity

    func testMatchingCardIDs_titleDifferentCase_matches() {
        let target = card(title: "Buy MILK")
        let result = CardQuery.matchingCardIDs(in: state(cards: [target]), query: "milk")
        XCTAssertEqual(result, [target.id])
    }

    // MARK: - OR combination

    func testMatchingCardIDs_orCombination_matchesAnyField() {
        let byTitle = card(title: "alpha")
        let byBody = card(title: "x", markdown: "alpha appears here")
        let neither = card(title: "y", markdown: "z")
        let result = CardQuery.matchingCardIDs(
            in: state(cards: [byTitle, byBody, neither]), query: "alpha")
        XCTAssertEqual(result, [byTitle.id, byBody.id])
    }

    // MARK: - Blank query = no filter

    func testMatchingCardIDs_emptyQuery_returnsAllCardIDs() {
        let a = card(title: "A")
        let b = card(title: "B")
        let result = CardQuery.matchingCardIDs(in: state(cards: [a, b]), query: "")
        XCTAssertEqual(result, [a.id, b.id])
    }

    func testMatchingCardIDs_whitespaceOnlyQuery_returnsAllCardIDs() {
        let a = card(title: "A")
        let b = card(title: "B")
        let result = CardQuery.matchingCardIDs(in: state(cards: [a, b]), query: "   \n\t ")
        XCTAssertEqual(result, [a.id, b.id])
    }

    // MARK: - No match

    func testMatchingCardIDs_noMatch_returnsEmpty() {
        let a = card(title: "A", markdown: "body")
        let result = CardQuery.matchingCardIDs(in: state(cards: [a]), query: "zzz-nope")
        XCTAssertTrue(result.isEmpty)
    }
}
