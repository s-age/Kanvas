import Synchronization
import XCTest
@testable import KanvasCore

/// `AddTextUseCaseImpl.execute` over a mock `TextService`: verifies it builds a `TextPlacement` and
/// forwards content + placement to the service's imperative `add` exactly once.
final class AddTextUseCaseTests: XCTestCase {

    private var mockTextService: MockTextService!
    private var sut: AddTextUseCaseImpl!

    override func setUp() {
        super.setUp()
        mockTextService = MockTextService()
        sut = AddTextUseCaseImpl(textService: mockTextService)
    }

    override func tearDown() {
        sut = nil
        mockTextService = nil
        super.tearDown()
    }

    private func request(content: String = "hi") -> AddTextRequest {
        AddTextRequest(cardID: UUID(), content: content, positionX: 5, positionY: 6, width: 200, height: 80)
    }

    func testExecute_callsAddOnce() async throws {
        _ = try await sut.execute(request())

        XCTAssertEqual(mockTextService.addCallCount, 1)
    }

    func testExecute_forwardsContent() async throws {
        _ = try await sut.execute(request(content: "free text"))

        XCTAssertEqual(mockTextService.lastAddContent, "free text")
    }

    func testExecute_forwardsPlacement() async throws {
        _ = try await sut.execute(request())

        XCTAssertEqual(mockTextService.lastAddPlacement?.position, CanvasPosition(x: 5, y: 6))
        XCTAssertEqual(mockTextService.lastAddPlacement?.size, TextSize(width: 200, height: 80))
    }
}

// MARK: - Test doubles

final class MockTextService: TextServiceProtocol, @unchecked Sendable {
    private let callState = Mutex<(count: Int, content: String?, placement: TextPlacement?)>((0, nil, nil))

    var addCallCount: Int { callState.withLock { $0.count } }
    var lastAddContent: String? { callState.withLock { $0.content } }
    var lastAddPlacement: TextPlacement? { callState.withLock { $0.placement } }

    private func echo() -> BoardState { BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: []) }

    func add(content: String, placement: TextPlacement, toCardCanvas cardID: Card.ID) async throws -> BoardState {
        callState.withLock { $0 = ($0.count + 1, content, placement) }
        return echo()
    }
    func duplicate(id: CanvasText.ID, at position: CanvasPosition) async throws -> BoardState { echo() }
    func edit(id: CanvasText.ID, content: String) async throws -> BoardState { echo() }
    func move(id: CanvasText.ID, to position: CanvasPosition) async throws -> BoardState { echo() }
    func resize(id: CanvasText.ID, to placement: TextPlacement) async throws -> BoardState { echo() }
    func setColor(id: CanvasText.ID, colorHex: String) async throws -> BoardState { echo() }
    func setFontSize(id: CanvasText.ID, fontSize: Double) async throws -> BoardState { echo() }
    func bringToFront(id: CanvasText.ID) async throws -> BoardState { echo() }
    func sendToBack(id: CanvasText.ID) async throws -> BoardState { echo() }
    func delete(id: CanvasText.ID) async throws -> BoardState { echo() }

    func adding(content: String, placement: TextPlacement, toCardCanvas cardID: Card.ID, in state: BoardState) -> BoardState { state }
    func duplicating(id: CanvasText.ID, at position: CanvasPosition, in state: BoardState) throws -> BoardState { state }
    func editing(id: CanvasText.ID, content: String, in state: BoardState) throws -> BoardState { state }
    func moving(id: CanvasText.ID, to position: CanvasPosition, in state: BoardState) throws -> BoardState { state }
    func resizing(id: CanvasText.ID, to placement: TextPlacement, in state: BoardState) throws -> BoardState { state }
    func settingColor(id: CanvasText.ID, colorHex: String, in state: BoardState) throws -> BoardState { state }
    func settingFontSize(id: CanvasText.ID, fontSize: Double, in state: BoardState) throws -> BoardState { state }
    func bringingToFront(id: CanvasText.ID, in state: BoardState) throws -> BoardState { state }
    func sendingToBack(id: CanvasText.ID, in state: BoardState) throws -> BoardState { state }
    func deleting(id: CanvasText.ID, from state: BoardState) throws -> BoardState { state }
}
