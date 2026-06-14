import XCTest
@testable import KanvasCore

/// Stickies and shapes share one canvas `sortIndex` space, so `StickyService` numbers a new /
/// re-stacked sticky against **both** collections (via `BoardState.nextFrontCanvasIndex`). These
/// pin the sticky-side half of that shared rule — the regression risk when shapes were added.
final class StickyServiceZOrderTests: XCTestCase {

    private var service: StickyService!

    override func setUp() {
        super.setUp()
        service = StickyService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func state(stickies: [Sticky] = [], shapes: [CanvasShape] = []) -> BoardState {
        BoardState(board: Board(title: "B"), columns: [], cards: [],
                   stickies: stickies, shapes: shapes)
    }

    private func placement() -> StickyPlacement {
        StickyPlacement(position: .zero, size: .default)
    }

    func testAdding_numbersAboveExistingShapeOnSameCard() {
        let cardID = UUID()
        let shape = CanvasShape(cardID: cardID, kind: "rectangle", position: .zero, sortIndex: 4)

        let result = service.adding(content: "a", placement: placement(),
                                    toCardCanvas: cardID, in: state(shapes: [shape]))

        XCTAssertEqual(result.stickies.first?.sortIndex, 5)
    }

    func testBringingToFront_liftsAboveAFrontmostShape() throws {
        let cardID = UUID()
        let sticky = Sticky(cardID: cardID, content: "a", position: .zero, sortIndex: 0)
        let shape = CanvasShape(cardID: cardID, kind: "rectangle", position: .zero, sortIndex: 9)

        let result = try service.bringingToFront(id: sticky.id, in: state(stickies: [sticky], shapes: [shape]))

        XCTAssertEqual(result.stickies.first?.sortIndex, 10)
    }
}
