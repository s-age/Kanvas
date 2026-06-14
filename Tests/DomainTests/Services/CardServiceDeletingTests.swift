import XCTest
@testable import KanvasCore

/// `CardService.deleting` cascade: deleting a card removes **every** child of its canvas — not just
/// stickies. These pin the fix for the leak where shapes / images / connectors (and, for images,
/// their snapshot placement) survived a card delete.
final class CardServiceDeletingTests: XCTestCase {

    private var service: CardService!

    override func setUp() {
        super.setUp()
        service = CardService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func state(cards: [Card] = [], stickies: [Sticky] = [], shapes: [CanvasShape] = [],
                       images: [CanvasImage] = [], connectors: [Connector] = []) -> BoardState {
        BoardState(board: Board(title: "B"), columns: [], cards: cards,
                   stickies: stickies, shapes: shapes, images: images, connectors: connectors)
    }

    func testDeleting_removesImagesOnTheCard() throws {
        let card = Card(columnID: UUID(), title: "C", sortIndex: 0)
        let image = CanvasImage(cardID: card.id, assetID: UUID(), position: .zero,
                                size: ImageSize(width: 100, height: 100), aspectRatio: 1, sortIndex: 0)

        let result = try service.deleting(id: card.id, from: state(cards: [card], images: [image]))

        XCTAssertTrue(result.images.isEmpty)
    }

    func testDeleting_keepsImagesOnOtherCards() throws {
        let card = Card(columnID: UUID(), title: "C", sortIndex: 0)
        let other = CanvasImage(cardID: UUID(), assetID: UUID(), position: .zero,
                                size: ImageSize(width: 100, height: 100), aspectRatio: 1, sortIndex: 0)

        let result = try service.deleting(id: card.id, from: state(cards: [card], images: [other]))

        XCTAssertEqual(result.images.count, 1)
    }

    func testDeleting_removesShapesOnTheCard() throws {
        let card = Card(columnID: UUID(), title: "C", sortIndex: 0)
        let shape = CanvasShape(cardID: card.id, kind: "rectangle", position: .zero, sortIndex: 0)

        let result = try service.deleting(id: card.id, from: state(cards: [card], shapes: [shape]))

        XCTAssertTrue(result.shapes.isEmpty)
    }

    func testDeleting_cascadesNestedCardSubtree() throws {
        // A → (task sticky) → B → (task sticky) → C. Deleting A must prune B and C, both cards'
        // canvas children, and the connecting task stickies — not just A's one level.
        let cardA = Card(columnID: UUID(), title: "A", sortIndex: 0)
        let cardB = Card(columnID: UUID(), title: "B", sortIndex: 1)
        let cardC = Card(columnID: UUID(), title: "C", sortIndex: 2)
        var taskOnA = Sticky(cardID: cardA.id, content: "→B", position: .zero, sortIndex: 0)
        taskOnA.linkedCardID = cardB.id
        var taskOnB = Sticky(cardID: cardB.id, content: "→C", position: .zero, sortIndex: 0)
        taskOnB.linkedCardID = cardC.id
        let freeOnC = Sticky(cardID: cardC.id, content: "leaf", position: .zero, sortIndex: 0)
        let shapeOnC = CanvasShape(cardID: cardC.id, kind: "rectangle", position: .zero, sortIndex: 1)

        let result = try service.deleting(
            id: cardA.id,
            from: state(cards: [cardA, cardB, cardC],
                        stickies: [taskOnA, taskOnB, freeOnC], shapes: [shapeOnC])
        )

        XCTAssertEqual(result.cards.map(\.id), [])
        XCTAssertTrue(result.stickies.isEmpty)
        XCTAssertTrue(result.shapes.isEmpty)
    }

    func testDeleting_cascade_keepsUnrelatedSubtree() throws {
        // A → B, plus an independent X → Y. Deleting A prunes A/B but never touches X/Y.
        let cardA = Card(columnID: UUID(), title: "A", sortIndex: 0)
        let cardB = Card(columnID: UUID(), title: "B", sortIndex: 1)
        let cardX = Card(columnID: UUID(), title: "X", sortIndex: 2)
        let cardY = Card(columnID: UUID(), title: "Y", sortIndex: 3)
        var taskOnA = Sticky(cardID: cardA.id, content: "→B", position: .zero, sortIndex: 0)
        taskOnA.linkedCardID = cardB.id
        var taskOnX = Sticky(cardID: cardX.id, content: "→Y", position: .zero, sortIndex: 0)
        taskOnX.linkedCardID = cardY.id

        let result = try service.deleting(
            id: cardA.id,
            from: state(cards: [cardA, cardB, cardX, cardY], stickies: [taskOnA, taskOnX])
        )

        XCTAssertEqual(Set(result.cards.map(\.id)), [cardX.id, cardY.id])
        XCTAssertEqual(result.stickies.map(\.id), [taskOnX.id])
    }

    func testDeleting_cascade_dropsConnectorToPrunedLinkingStickyOnSurvivingParentCanvas() throws {
        // Duplicate-link state: two task stickies both link to the deleted cardB — one on cardB's own
        // (doomed) canvas, one on parent cardA's *surviving* canvas. Deleting cardB prunes that
        // parent-canvas linking sticky (it now points at a doomed card); the connector wiring it on
        // cardA's still-live canvas would dangle. The by-cardID connector sweep can't reach it
        // (cardA is not doomed), so it must be dropped by endpoint.
        let cardA = Card(columnID: UUID(), title: "A", sortIndex: 0)
        let cardB = Card(columnID: UUID(), title: "B", sortIndex: 1)
        var linkOnBSelf = Sticky(cardID: cardB.id, content: "→B(self)", position: .zero, sortIndex: 0)
        linkOnBSelf.linkedCardID = cardB.id
        var linkOnA = Sticky(cardID: cardA.id, content: "→B", position: .zero, sortIndex: 0)
        linkOnA.linkedCardID = cardB.id
        let freeOnA = Sticky(cardID: cardA.id, content: "free", position: .zero, sortIndex: 1)
        let danglingConnector = Connector(cardID: cardA.id, sourceStickyID: linkOnA.id,
                                          sourceEdge: .right, targetStickyID: freeOnA.id,
                                          targetEdge: .left)

        let result = try service.deleting(
            id: cardB.id,
            from: state(cards: [cardA, cardB], stickies: [linkOnBSelf, linkOnA, freeOnA],
                        connectors: [danglingConnector])
        )

        XCTAssertTrue(result.connectors.isEmpty)
    }

    func testDeleting_unknownID_throwsNotFound() {
        let missingID = UUID()

        XCTAssertThrowsError(try service.deleting(id: missingID, from: state())) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Card", id: missingID))
        }
    }
}
