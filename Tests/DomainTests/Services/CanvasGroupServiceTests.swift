import XCTest
@testable import KanvasCore

/// `CanvasGroupService` — group move / delete over a multi-selection applied as ONE batch mutation
/// (ticket 4FF14DCF). Covers the pure transforms' routing (sticky / shape / image / connector),
/// stale-id tolerance, and the sticky→connector cascade interaction; plus the imperative verbs over
/// a `StubBoardRepository` to assert the whole batch opens the persistence boundary **once**.
final class CanvasGroupServiceTests: XCTestCase {

    private let cardID = UUID()

    private func makeService(_ repository: StubBoardRepository) -> CanvasGroupService {
        CanvasGroupService(
            repository: repository,
            stickyService: StickyService(repository: repository),
            shapeService: ShapeService(repository: repository),
            imageService: CanvasImageService(repository: repository,
                                             imageAssetRepository: StubImageAssetRepository(),
                                             diagnostics: SpyDiagnosticsLogger()),
            textService: TextService(repository: repository),
            connectorService: ConnectorService(repository: repository,
                                               stickyService: StickyService(repository: repository))
        )
    }

    private func sticky(_ sortIndex: Int = 0) -> Sticky {
        Sticky(cardID: cardID, content: "s", position: .zero, sortIndex: sortIndex)
    }

    private func shape(_ sortIndex: Int = 0) -> CanvasShape {
        CanvasShape(cardID: cardID, kind: "rectangle", position: .zero, sortIndex: sortIndex)
    }

    private func image(_ sortIndex: Int = 0) -> CanvasImage {
        CanvasImage(cardID: cardID, assetID: UUID(), position: .zero,
                    size: ImageSize(width: 100, height: 100), aspectRatio: 1, sortIndex: sortIndex)
    }

    private func state(stickies: [Sticky] = [], shapes: [CanvasShape] = [],
                       images: [CanvasImage] = [], connectors: [Connector] = []) -> BoardState {
        var state = BoardState(board: Board(title: "B"), columns: [],
                               cards: [Card(columnID: UUID(), title: "C", sortIndex: 0)],
                               stickies: stickies)
        state.shapes = shapes
        state.images = images
        state.connectors = connectors
        return state
    }

    // MARK: - movingGroup

    func testMovingGroup_movesEveryKindToItsTarget() throws {
        let aSticky = sticky()
        let aShape = shape()
        let anImage = image()
        let service = makeService(StubBoardRepository())
        let movements = [
            CanvasItemMovement(id: aSticky.id, position: CanvasPosition(x: 10, y: 11)),
            CanvasItemMovement(id: aShape.id, position: CanvasPosition(x: 20, y: 21)),
            CanvasItemMovement(id: anImage.id, position: CanvasPosition(x: 30, y: 31)),
        ]

        let result = try service.movingGroup(
            movements, in: state(stickies: [aSticky], shapes: [aShape], images: [anImage]))

        XCTAssertEqual(result.stickies.first { $0.id == aSticky.id }?.position, CanvasPosition(x: 10, y: 11))
        XCTAssertEqual(result.shapes.first { $0.id == aShape.id }?.position, CanvasPosition(x: 20, y: 21))
        XCTAssertEqual(result.images.first { $0.id == anImage.id }?.position, CanvasPosition(x: 30, y: 31))
    }

    func testMovingGroup_skipsStaleAndConnectorIDs_withoutThrowing() throws {
        let aSticky = sticky()
        let connector = Connector(cardID: cardID, sourceStickyID: aSticky.id, sourceEdge: .right,
                                  targetStickyID: aSticky.id, targetEdge: .left)
        let service = makeService(StubBoardRepository())
        let movements = [
            CanvasItemMovement(id: aSticky.id, position: CanvasPosition(x: 5, y: 6)),
            CanvasItemMovement(id: UUID(), position: CanvasPosition(x: 9, y: 9)),       // stale id
            CanvasItemMovement(id: connector.id, position: CanvasPosition(x: 9, y: 9)), // connectors don't move
        ]

        let result = try service.movingGroup(
            movements, in: state(stickies: [aSticky], connectors: [connector]))

        XCTAssertEqual(result.stickies.first { $0.id == aSticky.id }?.position, CanvasPosition(x: 5, y: 6))
    }

    // MARK: - deletingGroup

    func testDeletingGroup_removesEveryKind() throws {
        let aSticky = sticky()
        let aShape = shape()
        let anImage = image()
        let service = makeService(StubBoardRepository())

        let result = try service.deletingGroup(
            ids: [aSticky.id, aShape.id, anImage.id],
            in: state(stickies: [aSticky], shapes: [aShape], images: [anImage]))

        XCTAssertTrue(result.stickies.isEmpty)
        XCTAssertTrue(result.shapes.isEmpty)
        XCTAssertTrue(result.images.isEmpty)
    }

    func testDeletingGroup_stickyAndItsCascadedConnectorInOneBatch_isNoOpForConnector() throws {
        // The batch names both the sticky and a connector attached to it. Deleting the sticky
        // cascades the connector away; reaching the connector id afterwards must be a tolerated
        // no-op, not a `notFound`.
        let aSticky = sticky()
        let other = sticky(1)
        let connector = Connector(cardID: cardID, sourceStickyID: aSticky.id, sourceEdge: .right,
                                  targetStickyID: other.id, targetEdge: .left)
        let service = makeService(StubBoardRepository())

        let result = try service.deletingGroup(
            ids: [aSticky.id, connector.id],
            in: state(stickies: [aSticky, other], connectors: [connector]))

        XCTAssertEqual(result.stickies.map(\.id), [other.id])
        XCTAssertTrue(result.connectors.isEmpty)
    }

    func testDeletingGroup_toleratesAlreadyAbsentIDs() throws {
        let aSticky = sticky()
        let service = makeService(StubBoardRepository())

        let result = try service.deletingGroup(
            ids: [aSticky.id, UUID(), UUID()], in: state(stickies: [aSticky]))

        XCTAssertTrue(result.stickies.isEmpty)
    }

    // MARK: - Imperative verbs persist as a single mutation

    func testMoveGroup_opensThePersistenceBoundaryExactlyOnce() async throws {
        let stickies = (0..<5).map { sticky($0) }
        let stub = StubBoardRepository(state: state(stickies: stickies))
        let service = makeService(stub)
        let movements = stickies.map {
            CanvasItemMovement(id: $0.id, position: CanvasPosition(x: 7, y: 8))
        }

        _ = try await service.moveGroup(movements)

        XCTAssertEqual(stub.mutateCallCount, 1)
        let persisted = try stub.loadActiveBoard()
        XCTAssertTrue(persisted.stickies.allSatisfy { $0.position == CanvasPosition(x: 7, y: 8) })
    }

    func testDeleteGroup_opensThePersistenceBoundaryExactlyOnce() async throws {
        let stickies = (0..<5).map { sticky($0) }
        let stub = StubBoardRepository(state: state(stickies: stickies))
        let service = makeService(stub)

        _ = try await service.deleteGroup(ids: stickies.map(\.id))

        XCTAssertEqual(stub.mutateCallCount, 1)
        XCTAssertTrue(try stub.loadActiveBoard().stickies.isEmpty)
    }
}
