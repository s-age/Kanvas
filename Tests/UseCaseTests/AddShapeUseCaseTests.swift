import Synchronization
import XCTest
@testable import KanvasCore

/// `AddShapeUseCaseImpl.execute` over a mock `ShapeService`: verifies that the use case resolves the
/// `topology` raw value and forwards it to the service's imperative `add` exactly once, with the
/// correct `kind` and `topology`.
final class AddShapeUseCaseTests: XCTestCase {

    private var mockShapeService: MockShapeService!
    private var sut: AddShapeUseCaseImpl!

    override func setUp() {
        super.setUp()
        mockShapeService = MockShapeService()
        sut = AddShapeUseCaseImpl(shapeService: mockShapeService)
    }

    override func tearDown() {
        sut = nil
        mockShapeService = nil
        super.tearDown()
    }

    private func request(kind: String = "triangle", topology: String = "box") -> AddShapeRequest {
        AddShapeRequest(cardID: UUID(), kind: kind, topology: topology,
                        positionX: 0, positionY: 0, width: 100, height: 80)
    }

    // MARK: - execute

    func testExecute_callsAddOnce() async throws {
        _ = try await sut.execute(request())

        XCTAssertEqual(mockShapeService.addCallCount, 1)
    }

    func testExecute_forwardsKindToShapeService() async throws {
        _ = try await sut.execute(request(kind: "triangle", topology: "box"))

        XCTAssertEqual(mockShapeService.lastAddKind, "triangle")
    }

    func testExecute_resolvesTopologyRawValueAndForwardsToShapeService() async throws {
        _ = try await sut.execute(request(kind: "triangle", topology: "box"))

        XCTAssertEqual(mockShapeService.lastAddTopology, .box)
    }

    func testExecute_segmentTopology_forwardsSegment() async throws {
        _ = try await sut.execute(request(kind: "line", topology: "segment"))

        XCTAssertEqual(mockShapeService.lastAddTopology, .segment)
    }
}

// MARK: - Test doubles

private final class MockShapeService: ShapeServiceProtocol, @unchecked Sendable {
    private let callState = Mutex<(count: Int, kind: String?, topology: ShapeTopology?)>((0, nil, nil))
    private let emptyState = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])

    var addCallCount: Int { callState.withLock { $0.count } }
    var lastAddKind: String? { callState.withLock { $0.kind } }
    var lastAddTopology: ShapeTopology? { callState.withLock { $0.topology } }

    // Imperative verbs — the use case calls `add`.
    func add(spec: ShapeSpec, placement: ShapePlacement,
             toCardCanvas cardID: Card.ID) throws -> BoardState {
        callState.withLock { $0 = ($0.count + 1, spec.kind, spec.topology) }
        return emptyState
    }
    func move(id: CanvasShape.ID, to position: CanvasPosition) throws -> BoardState { emptyState }
    func resize(id: CanvasShape.ID, to placement: ShapePlacement, lineRising: Bool?) throws -> BoardState {
        emptyState
    }
    func setStrokeColor(id: CanvasShape.ID, colorHex: String) throws -> BoardState { emptyState }
    func setFillColor(id: CanvasShape.ID, colorHex: String?) throws -> BoardState { emptyState }
    func setStrokeWidth(id: CanvasShape.ID, width: Double) throws -> BoardState { emptyState }
    func bringToFront(id: CanvasShape.ID) throws -> BoardState { emptyState }
    func sendToBack(id: CanvasShape.ID) throws -> BoardState { emptyState }
    func delete(id: CanvasShape.ID) throws -> BoardState { emptyState }

    // Pure transforms — unused by this test.
    func adding(spec: ShapeSpec, placement: ShapePlacement,
                toCardCanvas cardID: Card.ID, in state: BoardState) -> BoardState { state }
    func moving(id: CanvasShape.ID, to position: CanvasPosition, in state: BoardState) -> BoardState { state }
    func resizing(id: CanvasShape.ID, to placement: ShapePlacement,
                  lineRising: Bool?, in state: BoardState) -> BoardState { state }
    func settingStrokeColor(id: CanvasShape.ID, colorHex: String, in state: BoardState) -> BoardState { state }
    func settingFillColor(id: CanvasShape.ID, colorHex: String?, in state: BoardState) -> BoardState { state }
    func settingStrokeWidth(id: CanvasShape.ID, width: Double, in state: BoardState) -> BoardState { state }
    func bringingToFront(id: CanvasShape.ID, in state: BoardState) -> BoardState { state }
    func sendingToBack(id: CanvasShape.ID, in state: BoardState) -> BoardState { state }
    func deleting(id: CanvasShape.ID, from state: BoardState) -> BoardState { state }
}
