import XCTest
@testable import KanvasCore

/// `BoardResponseMapper.toCardDetailResponse` maps domain `CanvasText` to `TextResponse`: it filters
/// to the card, sorts by `sortIndex`, and carries the domain bounds onto each `TextResponse` so
/// Presentation clamps against the same authoritative values. Exercised through the public
/// `toCardDetailResponse` path (matching how the sibling response mappers are tested).
final class BoardResponseMapperTextTests: XCTestCase {

    private let mapper = BoardResponseMapper()

    /// Builds a minimal `BoardState` with a single card and the given texts attached.
    private func state(cardID: UUID, _ texts: [CanvasText]) -> BoardState {
        let board = Board(title: "B")
        let column = Column(boardID: board.id, title: "Col", sortIndex: 0)
        let card = Card(id: cardID, columnID: column.id, title: "C", markdownContent: "", sortIndex: 0)
        var s = BoardState(board: board, columns: [column], cards: [card], stickies: [])
        s.texts = texts
        return s
    }

    private func text(cardID: UUID, content: String = "hi", sortIndex: Int = 0) -> CanvasText {
        CanvasText(cardID: cardID, content: content, position: CanvasPosition(x: 1, y: 2),
                   size: TextSize(width: 100, height: 50),
                   style: CanvasTextStyle(colorHex: "445566", fontSize: 18), sortIndex: sortIndex)
    }

    func testToCardDetailResponse_filtersTextsToCard() {
        let cardID = UUID()
        let texts = [text(cardID: cardID), text(cardID: UUID())]

        let detail = mapper.toCardDetailResponse(cardID: cardID, from: state(cardID: cardID, texts))

        XCTAssertEqual(detail?.texts.count, 1)
    }

    func testToCardDetailResponse_sortsTextsBySortIndex() {
        let cardID = UUID()
        let texts = [text(cardID: cardID, content: "second", sortIndex: 5),
                     text(cardID: cardID, content: "first", sortIndex: 1)]

        let detail = mapper.toCardDetailResponse(cardID: cardID, from: state(cardID: cardID, texts))

        XCTAssertEqual(detail?.texts.map(\.content), ["first", "second"])
    }

    func testToCardDetailResponse_carriesTextStyle() {
        let cardID = UUID()
        let detail = mapper.toCardDetailResponse(cardID: cardID, from: state(cardID: cardID, [text(cardID: cardID)]))

        XCTAssertEqual(detail?.texts.first?.textColorHex, "445566")
    }

    func testToCardDetailResponse_carriesTextFontSize() {
        let cardID = UUID()
        let detail = mapper.toCardDetailResponse(cardID: cardID, from: state(cardID: cardID, [text(cardID: cardID)]))

        XCTAssertEqual(detail?.texts.first?.fontSize, 18)
    }

    func testToCardDetailResponse_carriesTextMinWidthBound() {
        let cardID = UUID()
        let detail = mapper.toCardDetailResponse(cardID: cardID, from: state(cardID: cardID, [text(cardID: cardID)]))

        XCTAssertEqual(detail?.texts.first?.minWidth, TextSize.minWidth)
    }

    func testToCardDetailResponse_carriesTextMaxFontSizeBound() {
        let cardID = UUID()
        let detail = mapper.toCardDetailResponse(cardID: cardID, from: state(cardID: cardID, [text(cardID: cardID)]))

        XCTAssertEqual(detail?.texts.first?.maxFontSize, CanvasTextStyle.maxFontSize)
    }

    func testToCardDetailResponse_includesTexts() {
        let cardID = UUID()
        let detail = mapper.toCardDetailResponse(cardID: cardID, from: state(cardID: cardID, [text(cardID: cardID)]))

        XCTAssertEqual(detail?.texts.count, 1)
    }
}
