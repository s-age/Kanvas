import Synchronization
import XCTest
@testable import KanvasCore

/// `BoardViewModel.applyBoardMutation` (ticket 1DCBF9C9): a canvas mutation carries the open card's
/// refreshed detail, so the VM adopts it **directly** — without the redundant `LoadCardDetail`
/// disk read the old `applyBoard → refreshCardDetail` path always paid. When the mutation supplies
/// no detail for the open card, the VM falls back to a fresh load. These pin both halves with a
/// spy on `LoadCardDetailUseCase`.
@MainActor
final class BoardViewModelMutationDetailTests: XCTestCase {

    private var mockEdit: ConfigurableEditStickyUseCase!
    private var spyLoad: SpyLoadCardDetailUseCase!
    private var sut: BoardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockEdit = ConfigurableEditStickyUseCase()
        spyLoad = SpyLoadCardDetailUseCase()
        sut = makeBoardViewModel(loadCardDetail: spyLoad, editSticky: mockEdit)
    }

    override func tearDown() async throws {
        sut = nil
        spyLoad = nil
        mockEdit = nil
        try await super.tearDown()
    }

    /// Drives the open-card selection and lets its fire-and-forget detail refresh settle, then zeroes
    /// the spy so the assertion measures only the mutation under test.
    private func openCard(_ id: UUID) async {
        sut.selectCard(id: id)
        for _ in 0..<20 where spyLoad.callCount == 0 { await Task.yield() }
        spyLoad.reset()
    }

    func testCanvasMutation_adoptsReturnedDetail_withoutDiskRead() async {
        let cardID = UUID()
        await openCard(cardID)
        let detail = stubCardDetail(id: cardID, markdown: "after edit")
        mockEdit.response = BoardMutationResponse(board: stubBoardResponse(), cardDetail: detail)

        await sut.editSticky(id: UUID(), content: "x")

        XCTAssertEqual(sut.selectedCardDetail, detail)
        XCTAssertEqual(spyLoad.callCount, 0)  // adopted from the mutation — no reload
    }

    func testCanvasMutation_detailForDifferentCard_fallsBackToReload() async {
        let cardID = UUID()
        await openCard(cardID)
        // Detail is for some other card → not the open card → must reload.
        mockEdit.response = BoardMutationResponse(
            board: stubBoardResponse(), cardDetail: stubCardDetail(id: UUID(), markdown: "other")
        )

        await sut.editSticky(id: UUID(), content: "x")
        for _ in 0..<20 where spyLoad.callCount == 0 { await Task.yield() }

        XCTAssertEqual(spyLoad.callCount, 1)
    }

    func testCanvasMutation_nilDetail_fallsBackToReload() async {
        let cardID = UUID()
        await openCard(cardID)
        mockEdit.response = BoardMutationResponse(board: stubBoardResponse(), cardDetail: nil)

        await sut.editSticky(id: UUID(), content: "x")
        for _ in 0..<20 where spyLoad.callCount == 0 { await Task.yield() }

        XCTAssertEqual(spyLoad.callCount, 1)
    }
}

// MARK: - Configurable edit-sticky + spy load-card-detail

private final class ConfigurableEditStickyUseCase: AsyncUseCase, @unchecked Sendable {
    private let stored = Mutex<BoardMutationResponse?>(nil)
    var response: BoardMutationResponse? {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }

    func execute(_ request: EditStickyRequest) async throws -> BoardMutationResponse {
        stored.withLock { $0 } ?? BoardMutationResponse(board: stubBoardResponse(), cardDetail: nil)
    }
}

private final class SpyLoadCardDetailUseCase: LoadCardDetailUseCase, @unchecked Sendable {
    private let count = Mutex<Int>(0)
    var callCount: Int { count.withLock { $0 } }
    func reset() { count.withLock { $0 = 0 } }

    func execute(cardID: UUID) async throws -> CardDetailResponse? {
        count.withLock { $0 += 1 }
        return stubCardDetail(id: cardID, markdown: "reloaded")
    }
}

// MARK: - Fixtures

private func stubCardDetail(id: UUID, markdown: String) -> CardDetailResponse {
    CardDetailResponse(
        id: id, title: "Card", markdownContent: markdown,
        status: .todo, columnTitle: "To Do",
        schedule: nil, labels: [], assignee: nil, prURL: nil, completedAt: nil,
        stickies: [], shapes: [], images: [], texts: [], connectors: []
    )
}
