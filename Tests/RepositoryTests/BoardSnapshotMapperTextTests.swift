import XCTest
@testable import KanvasCore

/// `BoardSnapshotMapper` must round-trip free-text objects (content / geometry / colour / font /
/// sortIndex) and must decode a text-less snapshot into an empty collection.
final class BoardSnapshotMapperTextTests: XCTestCase {

    private func text(content: String = "hi", style: CanvasTextStyle = .default,
                      sortIndex: Int = 3) -> CanvasText {
        CanvasText(cardID: UUID(), content: content,
                   position: CanvasPosition(x: 1, y: 2),
                   size: TextSize(width: 120, height: 60), style: style, sortIndex: sortIndex)
    }

    private func state(with text: CanvasText) -> BoardState {
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.texts = [text]
        return state
    }

    func testRoundTrip_preservesContent() {
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: text(content: "hello world")))
        )

        XCTAssertEqual(restored.texts.first?.content, "hello world")
    }

    func testRoundTrip_preservesGeometry() {
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: text()))
        )

        XCTAssertEqual(restored.texts.first?.position, CanvasPosition(x: 1, y: 2))
        XCTAssertEqual(restored.texts.first?.size, TextSize(width: 120, height: 60))
    }

    func testRoundTrip_preservesStyle() {
        let style = CanvasTextStyle(colorHex: "112233", fontSize: 22)
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: text(style: style)))
        )

        XCTAssertEqual(restored.texts.first?.style.colorHex, "112233")
        XCTAssertEqual(restored.texts.first?.style.fontSize, 22)
    }

    func testRoundTrip_preservesSortIndex() {
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: text(sortIndex: 7)))
        )

        XCTAssertEqual(restored.texts.first?.sortIndex, 7)
    }

    func testDecode_textlessSnapshot_yieldsEmptyTexts() {
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"),
            columns: [], cards: [], stickies: [],
            shapes: nil, images: nil, connectors: nil, texts: nil, labels: nil, settings: nil
        )

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertTrue(restored.texts.isEmpty)
    }
}
