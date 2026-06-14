import XCTest
@testable import KanvasCore

/// `TextService` pure transforms: create/edit/move/resize/style/z-order/delete. The z-order tests
/// pin the key design rule — texts share the canvas `sortIndex` space with stickies/shapes/images,
/// so a new or re-stacked text numbers against all of them. The edit tests pin the auto-delete of an
/// emptied text (ticket 7C1D6316 決め事 2).
final class TextServiceTests: XCTestCase {

    private var service: TextService!

    override func setUp() {
        super.setUp()
        service = TextService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func state(stickies: [Sticky] = [], texts: [CanvasText] = []) -> BoardState {
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: stickies)
        state.texts = texts
        return state
    }

    private func placement() -> TextPlacement {
        TextPlacement(position: CanvasPosition(x: 10, y: 20), size: TextSize(width: 100, height: 40))
    }

    private func text(_ content: String = "hi", sortIndex: Int = 0, cardID: UUID = UUID()) -> CanvasText {
        CanvasText(cardID: cardID, content: content, position: CanvasPosition(x: 0, y: 0),
                   size: .default, sortIndex: sortIndex)
    }

    // MARK: - adding

    func testAdding_appendsTextWithContent() {
        let result = service.adding(content: "hello", placement: placement(),
                                    toCardCanvas: UUID(), in: state())

        XCTAssertEqual(result.texts.first?.content, "hello")
    }

    func testAdding_emptyCanvas_numbersFromZero() {
        let result = service.adding(content: "x", placement: placement(),
                                    toCardCanvas: UUID(), in: state())

        XCTAssertEqual(result.texts.first?.sortIndex, 0)
    }

    func testAdding_numbersAboveExistingStickyOnSameCard() {
        let cardID = UUID()
        let existing = Sticky(cardID: cardID, content: "s",
                              position: CanvasPosition(x: 0, y: 0), sortIndex: 5)

        let result = service.adding(content: "x", placement: placement(),
                                    toCardCanvas: cardID, in: state(stickies: [existing]))

        XCTAssertEqual(result.texts.first?.sortIndex, 6)
    }

    // MARK: - duplicating

    func testDuplicating_copiesContentAndStyle() throws {
        let cardID = UUID()
        var source = text("hello", sortIndex: 0, cardID: cardID)
        source.style = CanvasTextStyle(colorHex: "#112233", fontSize: source.style.fontSize)

        let result = try service.duplicating(
            id: source.id, at: CanvasPosition(x: 99, y: 88), in: state(texts: [source])
        )

        let copy = try XCTUnwrap(result.texts.first(where: { $0.id != source.id }))
        XCTAssertEqual(copy.content, "hello")
        XCTAssertEqual(copy.style.colorHex, "#112233")
    }

    func testDuplicating_placesCopyAtRequestedPosition() throws {
        let source = text("x", sortIndex: 0)
        let result = try service.duplicating(
            id: source.id, at: CanvasPosition(x: 99, y: 88), in: state(texts: [source])
        )

        let copy = try XCTUnwrap(result.texts.first(where: { $0.id != source.id }))
        XCTAssertEqual(copy.position, CanvasPosition(x: 99, y: 88))
    }

    func testDuplicating_numbersCopyToFront() throws {
        let cardID = UUID()
        let source = text("x", sortIndex: 3, cardID: cardID)
        let result = try service.duplicating(
            id: source.id, at: CanvasPosition(x: 0, y: 0), in: state(texts: [source])
        )

        let copy = try XCTUnwrap(result.texts.first(where: { $0.id != source.id }))
        XCTAssertEqual(copy.sortIndex, 4)
    }

    func testDuplicating_unknownID_throwsNotFound() {
        XCTAssertThrowsError(
            try service.duplicating(id: UUID(), at: CanvasPosition(x: 0, y: 0), in: state())
        )
    }

    // MARK: - editing (auto-delete on empty)

    func testEditing_setsContent() throws {
        let existing = text("old")
        let result = try service.editing(id: existing.id, content: "new", in: state(texts: [existing]))

        XCTAssertEqual(result.texts.first?.content, "new")
    }

    func testEditing_emptyContent_deletesText() throws {
        let existing = text("old")
        let result = try service.editing(id: existing.id, content: "", in: state(texts: [existing]))

        XCTAssertTrue(result.texts.isEmpty)
    }

    func testEditing_whitespaceOnlyContent_deletesText() throws {
        let existing = text("old")
        let result = try service.editing(id: existing.id, content: "   \n ", in: state(texts: [existing]))

        XCTAssertTrue(result.texts.isEmpty)
    }

    func testEditing_unknownID_throwsNotFound() {
        XCTAssertThrowsError(try service.editing(id: UUID(), content: "x", in: state())) { error in
            guard case OperationError.notFound = error else { return XCTFail("expected notFound") }
        }
    }

    // MARK: - moving / resizing

    func testMoving_setsPosition() throws {
        let existing = text()
        let result = try service.moving(id: existing.id, to: CanvasPosition(x: 7, y: 8),
                                        in: state(texts: [existing]))

        XCTAssertEqual(result.texts.first?.position, CanvasPosition(x: 7, y: 8))
    }

    func testResizing_clampsBelowMinimumWidth() throws {
        let existing = text()
        let result = try service.resizing(
            id: existing.id,
            to: TextPlacement(position: CanvasPosition(x: 0, y: 0), size: TextSize(width: 1, height: 1)),
            in: state(texts: [existing])
        )

        XCTAssertEqual(result.texts.first?.size.width, TextSize.minWidth)
    }

    // MARK: - style

    func testSettingColor_setsColorHex() throws {
        let existing = text()
        let result = try service.settingColor(id: existing.id, colorHex: "AABBCC", in: state(texts: [existing]))

        XCTAssertEqual(result.texts.first?.style.colorHex, "AABBCC")
    }

    func testSettingFontSize_clampsAboveMaximum() throws {
        let existing = text()
        let result = try service.settingFontSize(id: existing.id, fontSize: 9_999, in: state(texts: [existing]))

        XCTAssertEqual(result.texts.first?.style.fontSize, CanvasTextStyle.maxFontSize)
    }

    // MARK: - z-order

    func testBringingToFront_numbersAboveSibling() throws {
        let cardID = UUID()
        let a = text("a", sortIndex: 0, cardID: cardID)
        let b = text("b", sortIndex: 5, cardID: cardID)

        let result = try service.bringingToFront(id: a.id, in: state(texts: [a, b]))

        XCTAssertEqual(result.texts.first(where: { $0.id == a.id })?.sortIndex, 6)
    }

    func testSendingToBack_numbersBelowSibling() throws {
        let cardID = UUID()
        let a = text("a", sortIndex: 5, cardID: cardID)
        let b = text("b", sortIndex: 0, cardID: cardID)

        let result = try service.sendingToBack(id: a.id, in: state(texts: [a, b]))

        XCTAssertEqual(result.texts.first(where: { $0.id == a.id })?.sortIndex, -1)
    }

    // MARK: - deleting

    func testDeleting_removesText() throws {
        let existing = text()
        let result = try service.deleting(id: existing.id, from: state(texts: [existing]))

        XCTAssertTrue(result.texts.isEmpty)
    }

    func testDeleting_unknownID_throwsNotFound() {
        XCTAssertThrowsError(try service.deleting(id: UUID(), from: state())) { error in
            guard case OperationError.notFound = error else { return XCTFail("expected notFound") }
        }
    }
}
