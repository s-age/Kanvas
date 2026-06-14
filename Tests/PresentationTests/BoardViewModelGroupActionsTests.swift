import Synchronization
import XCTest
@testable import KanvasCore

/// `BoardViewModel.moveSelected` / `deleteSelected` — the multi-select group actions forward the
/// whole selection to the batch use cases (ticket 4FF14DCF). These pin the empty-batch guard (an
/// empty selection must NOT open the use case, which would otherwise be a no-op flock + write + undo
/// entry) and the happy path (a non-empty batch invokes the use case exactly once). A non-nil
/// `selectedCardDetail` is established first via `openCard`, so the empty branch is exercised
/// distinctly from the `guard let detail` branch.
@MainActor
final class BoardViewModelGroupActionsTests: XCTestCase {

    private var moveSpy: CountingMoveGroupUseCase!
    private var deleteSpy: CountingDeleteGroupUseCase!
    private var spyLoad: SpyLoadCardDetailUseCase!
    private var sut: BoardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        moveSpy = CountingMoveGroupUseCase()
        deleteSpy = CountingDeleteGroupUseCase()
        spyLoad = SpyLoadCardDetailUseCase()
        sut = makeBoardViewModel(loadCardDetail: spyLoad, moveGroup: moveSpy, deleteGroup: deleteSpy)
    }

    override func tearDown() async throws {
        sut = nil
        spyLoad = nil
        deleteSpy = nil
        moveSpy = nil
        try await super.tearDown()
    }

    /// Selects a card and waits until its fire-and-forget detail refresh has actually assigned
    /// `selectedCardDetail` (not merely fired the load) — so the action under test sees a non-nil
    /// detail and the empty-batch guard is exercised distinctly from the `guard let detail` branch.
    private func openCard(_ id: UUID) async {
        sut.selectCard(id: id)
        for _ in 0..<50 where sut.selectedCardDetail == nil { await Task.yield() }
    }

    func testMoveSelected_emptyBatch_doesNotInvokeUseCase() async {
        await openCard(UUID())
        await sut.moveSelected([])
        XCTAssertEqual(moveSpy.callCount, 0)
    }

    func testMoveSelected_nonEmptyBatch_invokesUseCaseOnce() async {
        await openCard(UUID())
        await sut.moveSelected([CanvasDragMove(id: UUID(), worldX: 1, worldY: 2)])
        XCTAssertEqual(moveSpy.callCount, 1)
    }

    func testDeleteSelected_emptyBatch_doesNotInvokeUseCase() async {
        await openCard(UUID())
        await sut.deleteSelected(ids: [])
        XCTAssertEqual(deleteSpy.callCount, 0)
    }

    func testDeleteSelected_nonEmptyBatch_invokesUseCaseOnce() async {
        await openCard(UUID())
        await sut.deleteSelected(ids: [UUID()])
        XCTAssertEqual(deleteSpy.callCount, 1)
    }
}

// MARK: - Counting group use cases + spy load-card-detail

private final class CountingMoveGroupUseCase: AsyncUseCase, @unchecked Sendable {
    private let count = Mutex<Int>(0)
    var callCount: Int { count.withLock { $0 } }
    func execute(_ request: MoveCanvasGroupRequest) async throws -> BoardMutationResponse {
        count.withLock { $0 += 1 }
        return BoardMutationResponse(board: stubBoardResponse(), cardDetail: nil)
    }
}

private final class CountingDeleteGroupUseCase: AsyncUseCase, @unchecked Sendable {
    private let count = Mutex<Int>(0)
    var callCount: Int { count.withLock { $0 } }
    func execute(_ request: DeleteCanvasGroupRequest) async throws -> BoardMutationResponse {
        count.withLock { $0 += 1 }
        return BoardMutationResponse(board: stubBoardResponse(), cardDetail: nil)
    }
}

private final class SpyLoadCardDetailUseCase: LoadCardDetailUseCase, @unchecked Sendable {
    private let count = Mutex<Int>(0)
    var callCount: Int { count.withLock { $0 } }
    func execute(cardID: UUID) async throws -> CardDetailResponse? {
        count.withLock { $0 += 1 }
        return stubCardDetail(id: cardID)
    }
}

// MARK: - Fixtures

private func stubCardDetail(id: UUID) -> CardDetailResponse {
    CardDetailResponse(
        id: id, title: "Card", markdownContent: "",
        status: .todo, columnTitle: "To Do",
        schedule: nil, labels: [], assignee: nil, prURL: nil, completedAt: nil,
        stickies: [], shapes: [], images: [], texts: [], connectors: []
    )
}
