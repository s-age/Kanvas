import Synchronization
import XCTest
@testable import KanvasCore

/// `BoardViewModel.addShape` builds the correct `AddShapeRequest` (kind + topology raw value) and
/// applies the returned board. Uses a mock `AddShapeUseCase` to confirm the request is
/// forwarded exactly once with the correct fields, and that `error` stays nil on success.
@MainActor
final class BoardViewModelAddShapeTests: XCTestCase {

    private var mockAddShape: MockAddShapeUseCase!
    private var sut: BoardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockAddShape = MockAddShapeUseCase()
        sut = makeBoardViewModel(addShape: mockAddShape)
    }

    override func tearDown() async throws {
        sut = nil
        mockAddShape = nil
        try await super.tearDown()
    }

    // MARK: - addShape

    func testAddShape_callsUseCaseOnce() async {
        await sut.addShape(cardID: UUID(), draft: ShapeDraft(
            worldX: 0, worldY: 0, kind: "triangle", topology: .box,
            defaultWidth: 100, defaultHeight: 80
        ))

        XCTAssertEqual(mockAddShape.executeCallCount, 1)
    }

    func testAddShape_forwardsKindToRequest() async {
        await sut.addShape(cardID: UUID(), draft: ShapeDraft(
            worldX: 0, worldY: 0, kind: "triangle", topology: .box,
            defaultWidth: 100, defaultHeight: 80
        ))

        XCTAssertEqual(mockAddShape.lastRequest?.kind, "triangle")
    }

    func testAddShape_forwardsTopologyRawValueToRequest() async {
        await sut.addShape(cardID: UUID(), draft: ShapeDraft(
            worldX: 0, worldY: 0, kind: "triangle", topology: .box,
            defaultWidth: 100, defaultHeight: 80
        ))

        XCTAssertEqual(mockAddShape.lastRequest?.topology, "box")
    }

    func testAddShape_appliesReturnedBoard() async {
        let boardID = UUID()
        mockAddShape.response = stubBoardMutation(id: boardID)

        await sut.addShape(cardID: UUID(), draft: ShapeDraft(
            worldX: 0, worldY: 0, kind: "triangle", topology: .box,
            defaultWidth: 100, defaultHeight: 80
        ))

        XCTAssertEqual(sut.board?.board.id, boardID)
    }

    func testAddShape_noErrorOnSuccess() async {
        await sut.addShape(cardID: UUID(), draft: ShapeDraft(
            worldX: 0, worldY: 0, kind: "triangle", topology: .box,
            defaultWidth: 100, defaultHeight: 80
        ))

        XCTAssertNil(sut.error)
    }
}

// MARK: - Mock AddShapeUseCaseImpl

private final class MockAddShapeUseCase: AsyncUseCase, @unchecked Sendable {
    private let state = Mutex<(request: AddShapeRequest?, callCount: Int, response: BoardMutationResponse?)>(
        (nil, 0, nil)
    )

    var lastRequest: AddShapeRequest? { state.withLock { $0.request } }
    var executeCallCount: Int { state.withLock { $0.callCount } }
    var response: BoardMutationResponse? {
        get { state.withLock { $0.response } }
        set { state.withLock { $0.response = newValue } }
    }

    func execute(_ request: AddShapeRequest) async throws -> BoardMutationResponse {
        let r = state.withLock { s -> BoardMutationResponse? in
            s = (request, s.callCount + 1, s.response)
            return s.response
        }
        return r ?? stubBoardMutation()
    }
}
