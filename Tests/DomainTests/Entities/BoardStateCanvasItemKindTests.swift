import XCTest
@testable import KanvasCore

/// `BoardState.canvasItemKind(of:)` — the id→kind routing primitive for group operations. Resolves
/// an id to the canvas collection that owns it (stickies / shapes / images / connectors), or `nil`
/// for a stale id.
final class BoardStateCanvasItemKindTests: XCTestCase {

    private let cardID = UUID()

    private func makeState() -> (BoardState, sticky: UUID, shape: UUID, image: UUID, text: UUID, connector: UUID) {
        let sticky = Sticky(cardID: cardID, content: "s", position: .zero, sortIndex: 0)
        let other = Sticky(cardID: cardID, content: "o", position: .zero, sortIndex: 1)
        let shape = CanvasShape(cardID: cardID, kind: "rectangle", position: .zero, sortIndex: 2)
        let image = CanvasImage(cardID: cardID, assetID: UUID(), position: .zero,
                                size: ImageSize(width: 10, height: 10), aspectRatio: 1, sortIndex: 3)
        let text = CanvasText(cardID: cardID, content: "t", position: .zero, sortIndex: 4)
        let connector = Connector(cardID: cardID, sourceStickyID: sticky.id, sourceEdge: .right,
                                  targetStickyID: other.id, targetEdge: .left)
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [],
                               stickies: [sticky, other])
        state.shapes = [shape]
        state.images = [image]
        state.texts = [text]
        state.connectors = [connector]
        return (state, sticky.id, shape.id, image.id, text.id, connector.id)
    }

    func testResolvesEachKind() {
        let (state, sticky, shape, image, text, connector) = makeState()
        XCTAssertEqual(state.canvasItemKind(of: sticky), .sticky)
        XCTAssertEqual(state.canvasItemKind(of: shape), .shape)
        XCTAssertEqual(state.canvasItemKind(of: image), .image)
        XCTAssertEqual(state.canvasItemKind(of: text), .text)
        XCTAssertEqual(state.canvasItemKind(of: connector), .connector)
    }

    func testUnknownIDResolvesToNil() {
        let (state, _, _, _, _, _) = makeState()
        XCTAssertNil(state.canvasItemKind(of: UUID()))
    }
}
