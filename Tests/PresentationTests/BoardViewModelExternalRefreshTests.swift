import Synchronization
import XCTest
@testable import KanvasCore

/// `BoardViewModel.load()` (ticket 8DCB811D): the external-change watcher path must reload the store
/// **once**, not three times. `load()` now executes a single `LoadBoardViewState` use case that
/// carries the board, the picker list, and — keyed by the open card id it passes — that card's
/// refreshed detail, so the VM adopts the detail directly instead of paying a second `LoadCardDetail`
/// disk read (the old `loadActiveBoard → loadBoards → refreshCardDetail → loadActiveBoard` chain).
/// These pin: one combined read, the open card id is forwarded (so external edits still surface,
/// ticket 18CA57E0), and the detail is adopted without a separate card-detail read.
@MainActor
final class BoardViewModelExternalRefreshTests: XCTestCase {

    private var spyViewState: SpyLoadBoardViewStateUseCase!
    private var spyCardDetail: CountingLoadCardDetailUseCase!
    private var sut: BoardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        spyViewState = SpyLoadBoardViewStateUseCase()
        spyCardDetail = CountingLoadCardDetailUseCase()
        sut = makeBoardViewModel(loadBoardViewState: spyViewState, loadCardDetail: spyCardDetail)
    }

    override func tearDown() async throws {
        sut = nil
        spyCardDetail = nil
        spyViewState = nil
        try await super.tearDown()
    }

    /// Selects a card and lets its fire-and-forget detail refresh settle, then zeroes the card-detail
    /// spy so a later assertion measures only the reads `load()` itself triggers.
    private func openCard(_ id: UUID) async {
        sut.selectCard(id: id)
        _ = await waitUntil { self.spyCardDetail.callCount > 0 }
        spyCardDetail.reset()
    }

    func testLoad_executesCombinedReadExactlyOnce() async {
        await sut.load()

        XCTAssertEqual(spyViewState.executeCount, 1)
    }

    func testLoad_forwardsOpenCardID() async {
        let cardID = UUID()
        await openCard(cardID)

        await sut.load()

        XCTAssertEqual(spyViewState.lastOpenCardID, cardID)
    }

    func testLoad_adoptsCarriedDetail_withoutSecondCardDetailRead() async {
        let cardID = UUID()
        await openCard(cardID)
        let detail = stubCardDetail(id: cardID)
        spyViewState.response = BoardViewStateResponse(
            board: stubBoardResponse(), boardList: stubBoardListResponse(), cardDetail: detail,
            matchedCardIDs: nil, matchedQuery: ""
        )

        await sut.load()

        // Adoption is synchronous inside `load()` (no `refreshCardDetail` Task is spawned when the
        // snapshot carries the open card's detail), so the count is deterministically zero here — no
        // fixed-count settle wait needed.
        XCTAssertEqual(spyCardDetail.callCount, 0)  // adopted from the combined read — no second read
    }

    func testLoad_publishesCarriedDetailForOpenCard() async {
        let cardID = UUID()
        await openCard(cardID)
        let detail = stubCardDetail(id: cardID)
        spyViewState.response = BoardViewStateResponse(
            board: stubBoardResponse(), boardList: stubBoardListResponse(), cardDetail: detail,
            matchedCardIDs: nil, matchedQuery: ""
        )

        await sut.load()

        XCTAssertEqual(sut.selectedCardDetail, detail)
    }

    /// The open card was deleted by the other process: the combined read carries no detail for it, so
    /// `load()` must fall back to exactly one card-detail reload (the rare second read) rather than
    /// adopt — and never silently leave stale detail published.
    func testLoad_openCardMissingFromSnapshot_fallsBackToOneReload() async {
        let cardID = UUID()
        await openCard(cardID)
        // Snapshot has no detail for the open card (it no longer resolves in the decoded state).
        spyViewState.response = BoardViewStateResponse(
            board: stubBoardResponse(), boardList: stubBoardListResponse(), cardDetail: nil,
            matchedCardIDs: nil, matchedQuery: ""
        )

        await sut.load()
        let reloaded = await waitUntil { self.spyCardDetail.callCount == 1 }
        // Then settle: give any spurious second read a chance to land before asserting, so this
        // pins "exactly one reload" (the single fallback path) rather than "at least one" — a
        // regression that re-introduced a second store read would surface here, not pass silently.
        _ = await waitUntil { self.spyCardDetail.callCount > 1 }

        XCTAssertTrue(reloaded)
        XCTAssertEqual(spyCardDetail.callCount, 1)
    }
}

// MARK: - Spies

private final class SpyLoadBoardViewStateUseCase: AsyncUseCase, @unchecked Sendable {
    private let count = Mutex(0)
    private let openCardID = Mutex<UUID?>(nil)
    private let stored = Mutex<BoardViewStateResponse?>(nil)

    var executeCount: Int { count.withLock { $0 } }
    var lastOpenCardID: UUID? { openCardID.withLock { $0 } }
    var response: BoardViewStateResponse? {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }

    func execute(_ request: LoadBoardViewStateRequest) async throws -> BoardViewStateResponse {
        count.withLock { $0 += 1 }
        openCardID.withLock { $0 = request.openCardID }
        return stored.withLock { $0 }
            ?? BoardViewStateResponse(board: stubBoardResponse(), boardList: stubBoardListResponse(),
                                      cardDetail: nil, matchedCardIDs: nil, matchedQuery: "")
    }
}

private final class CountingLoadCardDetailUseCase: LoadCardDetailUseCase, @unchecked Sendable {
    private let count = Mutex(0)
    var callCount: Int { count.withLock { $0 } }
    func reset() { count.withLock { $0 = 0 } }

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
