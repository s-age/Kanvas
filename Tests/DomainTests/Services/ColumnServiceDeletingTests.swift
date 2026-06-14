import XCTest
@testable import KanvasCore

/// `ColumnService.deleting` cascade: deleting a column removes its cards and **all** their canvas
/// children, including image placements (mirrors `CardService.deleting`). Pins the leak fix.
final class ColumnServiceDeletingTests: XCTestCase {

    private var service: ColumnService!

    override func setUp() {
        super.setUp()
        service = ColumnService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testDeleting_removesImagesOfCardsInTheColumn() throws {
        let column = Column(boardID: UUID(), title: "Col", sortIndex: 0)
        let card = Card(columnID: column.id, title: "C", sortIndex: 0)
        let image = CanvasImage(cardID: card.id, assetID: UUID(), position: .zero,
                                size: ImageSize(width: 100, height: 100), aspectRatio: 1, sortIndex: 0)
        let state = BoardState(board: Board(title: "B"), columns: [column], cards: [card],
                               stickies: [], shapes: [], images: [image])

        let result = try service.deleting(id: column.id, from: state)

        XCTAssertTrue(result.images.isEmpty)
    }

    func testDeleting_cascadesNestedSubCardInAnotherColumn() throws {
        // A card in the deleted column carries a task sticky linking to a sub-card that lives in a
        // *different* column. The sub-card is not among the column's own cards, so a one-level prune
        // would strand it (and its canvas). The cascade must follow the drill-down link across columns.
        let board = Board(title: "B")
        let colToDelete = Column(boardID: board.id, title: "Del", sortIndex: 0)
        let otherColumn = Column(boardID: board.id, title: "Keep", sortIndex: 1)
        let cardInColumn = Card(columnID: colToDelete.id, title: "host", sortIndex: 0)
        let subCard = Card(columnID: otherColumn.id, title: "sub", sortIndex: 0)
        var taskSticky = Sticky(cardID: cardInColumn.id, content: "→sub", position: .zero, sortIndex: 0)
        taskSticky.linkedCardID = subCard.id
        let childOfSub = Sticky(cardID: subCard.id, content: "child", position: .zero, sortIndex: 0)
        let state = BoardState(board: board, columns: [colToDelete, otherColumn],
                               cards: [cardInColumn, subCard], stickies: [taskSticky, childOfSub])

        let result = try service.deleting(id: colToDelete.id, from: state)

        XCTAssertFalse(result.cards.contains { $0.id == subCard.id })
        XCTAssertTrue(result.stickies.isEmpty)
    }

    func testDeleting_unknownID_throwsNotFound() {
        let missingID = UUID()
        let state = BoardState(board: Board(title: "B"), columns: [], cards: [],
                               stickies: [], shapes: [], images: [])

        XCTAssertThrowsError(try service.deleting(id: missingID, from: state)) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Column", id: missingID))
        }
    }
}
