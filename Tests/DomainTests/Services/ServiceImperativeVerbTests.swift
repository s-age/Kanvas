import XCTest
@testable import KanvasCore

/// The Shape-1 **imperative verbs** that own the `repository.mutate` boundary — one representative
/// verb per Domain Service. The per-service `*Tests` files exercise the pure gerund transforms
/// directly; these instead drive the imperative wrapper over a seeded `StubBoardRepository` and
/// assert the change is **persisted** (read back via `loadActiveBoard()`), so a wrapper that forgot to call
/// `mutate`, or wired the wrong gerund, fails here. (`ConnectorService.add`'s create-target branch
/// is covered separately by `AddConnectorUseCaseTests` over a real `BoardRepository`.)
final class ServiceImperativeVerbTests: XCTestCase {

    private func seededStub(_ state: BoardState) -> StubBoardRepository { StubBoardRepository(state: state) }

    // MARK: - CardService

    func testCardAdd_persistsCardInColumn() async throws {
        let boardID = UUID()
        let column = Column(boardID: boardID, title: "A", sortIndex: 0)
        let stub = seededStub(BoardState(board: Board(id: boardID, title: "B"),
                                         columns: [column], cards: [], stickies: []))
        let service = CardService(repository: stub)
        let seed = CardSeed(title: "Task")

        _ = try await service.add(seed, columnID: column.id)

        let persisted = try stub.loadActiveBoard()
        XCTAssertEqual(persisted.cards.first { $0.id == seed.id }?.title, "Task")
    }

    func testCardDelete_removesPersistedCard() async throws {
        let boardID = UUID()
        let column = Column(boardID: boardID, title: "A", sortIndex: 0)
        let seed = CardSeed(title: "Doomed")
        // Build the seeded state via the (separately tested) pure gerund so we need no Card init here.
        let initial = CardService(repository: StubBoardRepository())
            .adding(seed, columnID: column.id,
                    to: BoardState(board: Board(id: boardID, title: "B"),
                                   columns: [column], cards: [], stickies: []))
        let stub = seededStub(initial)
        let service = CardService(repository: stub)

        _ = try await service.delete(id: seed.id)

        XCTAssertFalse(try stub.loadActiveBoard().cards.contains { $0.id == seed.id })
    }

    // MARK: - ColumnService

    func testColumnAdd_persistsColumnOnActiveBoard() async throws {
        let boardID = UUID()
        let stub = seededStub(BoardState(board: Board(id: boardID, title: "B"),
                                         columns: [], cards: [], stickies: []))
        let service = ColumnService(repository: stub)

        _ = try await service.add(title: "Backlog")

        let persisted = try stub.loadActiveBoard()
        XCTAssertEqual(persisted.columns.map(\.title), ["Backlog"])
        XCTAssertEqual(persisted.columns.first?.boardID, boardID)
    }

    // MARK: - StickyService

    func testStickyDelete_removesPersistedSticky() async throws {
        let cardID = UUID()
        let sticky = Sticky(cardID: cardID, content: "x", position: .zero, sortIndex: 0)
        let stub = seededStub(BoardState(board: Board(title: "B"), columns: [], cards: [],
                                         stickies: [sticky]))
        let service = StickyService(repository: stub)

        _ = try await service.delete(id: sticky.id)

        XCTAssertFalse(try stub.loadActiveBoard().stickies.contains { $0.id == sticky.id })
    }

    // MARK: - ShapeService

    func testShapeDelete_removesPersistedShape() async throws {
        let cardID = UUID()
        let placement = ShapePlacement(position: CanvasPosition(x: 0, y: 0),
                                       size: ShapeSize(width: 100, height: 80))
        // Seed via the pure gerund (no CanvasShape init needed), then drive the imperative delete.
        let initial = ShapeService(repository: StubBoardRepository())
            .adding(spec: ShapeSpec(kind: "ellipse", topology: .box), placement: placement,
                    toCardCanvas: cardID,
                    in: BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: []))
        let shapeID = try XCTUnwrap(initial.shapes.first?.id)
        let stub = seededStub(initial)
        let service = ShapeService(repository: stub)

        _ = try await service.delete(id: shapeID)

        XCTAssertFalse(try stub.loadActiveBoard().shapes.contains { $0.id == shapeID })
    }

    // MARK: - ConnectorService

    func testConnectorDelete_removesPersistedConnector() async throws {
        let cardID = UUID()
        let connector = Connector(cardID: cardID, sourceStickyID: UUID(), sourceEdge: .right,
                                  targetStickyID: UUID(), targetEdge: .left)
        var seeded = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        seeded.connectors = [connector]
        let stub = seededStub(seeded)
        let service = ConnectorService(repository: stub,
                                       stickyService: StickyService(repository: StubBoardRepository()))

        _ = try await service.delete(id: connector.id)

        XCTAssertTrue(try stub.loadActiveBoard().connectors.isEmpty)
    }

    // MARK: - LabelService

    func testLabelAdd_persistsLabel() async throws {
        let stub = seededStub(BoardState(board: Board(title: "B"), columns: [], cards: [],
                                         stickies: [], labels: []))
        let service = LabelService(repository: stub)

        _ = try await service.add(name: "Urgent", colorHex: "FF0000")

        XCTAssertEqual(try stub.loadActiveBoard().labels.map(\.name), ["Urgent"])
    }

    // MARK: - CanvasImageService (also persists the asset bytes it now owns)

    func testImageAdd_persistsPlacementAndAssetBytesRoundTrip() async throws {
        let cardID = UUID()
        let stub = seededStub(BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: []))
        let service = CanvasImageService(repository: stub, imageAssetRepository: StubImageAssetRepository(),
                                         diagnostics: SpyDiagnosticsLogger())
        let bytes = Data([0x1, 0x2, 0x3])

        let result = try await service.add(imageData: bytes,
                                     naturalSize: NaturalSize(width: 100, height: 50),
                                     position: CanvasPosition(x: 0, y: 0), toCardCanvas: cardID)

        let assetID = try XCTUnwrap(result.images.first?.assetID)
        XCTAssertEqual(try stub.loadActiveBoard().images.count, 1)
        let roundTripped = try await service.loadImageData(assetID: assetID)
        XCTAssertEqual(roundTripped, bytes)
    }

    // MARK: - BoardManagementService

    func testAddBoard_persistsTitledBoard() async throws {
        let stub = seededStub(BoardState(board: Board(title: "First"), columns: [], cards: [], stickies: []))
        let service = BoardManagementService(repository: stub,
                                             columnService: ColumnService(repository: stub),
                                             diagnostics: SpyDiagnosticsLogger())

        let result = try await service.addBoard(title: "Second")

        XCTAssertEqual(result.board.title, "Second")
        XCTAssertEqual(try stub.loadActiveBoard().board.title, "Second")
    }

    func testUndo_reportsNothingToUndoWhenNoHistory() async throws {
        let stub = seededStub(BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: []))
        let service = BoardManagementService(repository: stub,
                                             columnService: ColumnService(repository: stub),
                                             diagnostics: SpyDiagnosticsLogger())

        let undone = try await service.undo()
        XCTAssertEqual(undone, .nothingToUndo)
    }
}
