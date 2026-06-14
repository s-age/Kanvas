import XCTest
@testable import KanvasCore

/// `BoardViewModel` card-search behaviour (ticket 59B10FBA): a debounced `searchText` edit runs the
/// `SearchCardsUseCase` and publishes `matchedCardIDs`; a blank query clears the filter to `nil`; a
/// board switch clears the field + filter; `isCardVisible` reflects the filter.
@MainActor
final class BoardViewModelSearchTests: XCTestCase {

    private var search: ConfigurableSearchCards!
    private var sut: BoardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        search = ConfigurableSearchCards()
        sut = makeBoardViewModel(search: search)
    }

    override func tearDown() async throws {
        sut = nil
        search = nil
        try await super.tearDown()
    }

    /// Waits past the ~200ms search debounce, then yields until `condition` holds (or the budget
    /// runs out). The debounce is real wall-clock, so a plain `Task.yield` loop is not enough.
    private func waitForDebounce(_ condition: @escaping () -> Bool) async -> Bool {
        try? await Task.sleep(for: .milliseconds(300))
        return await waitUntil(condition)
    }

    func testSearchText_nonBlank_publishesMatchedCardIDs() async {
        let matched: Set<UUID> = [UUID(), UUID()]
        search.stubbedMatches = matched
        sut.searchText = "milk"
        let settled = await waitForDebounce { self.sut.matchedCardIDs == matched }
        XCTAssertTrue(settled)
    }

    func testSearchText_nonBlank_forwardsTrimmedQuery() async {
        sut.searchText = "  milk  "
        _ = await waitForDebounce { self.search.lastQuery != nil }
        XCTAssertEqual(search.lastQuery, "milk")
    }

    func testSearchText_blank_clearsFilterWithoutCallingUseCase() async {
        sut.searchText = "   "
        // Give any (incorrectly scheduled) debounced task time to fire.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(sut.matchedCardIDs)
        XCTAssertEqual(search.callCount, 0)
    }

    func testSearchText_emptyAfterMatch_resetsFilterToNil() async {
        search.stubbedMatches = [UUID()]
        sut.searchText = "milk"
        _ = await waitForDebounce { self.sut.matchedCardIDs != nil }
        sut.searchText = ""
        XCTAssertNil(sut.matchedCardIDs)
    }

    func testRapidTyping_runsSearchOnlyForLatestQuery() async {
        sut.searchText = "a"
        sut.searchText = "ab"
        sut.searchText = "abc"
        _ = await waitForDebounce { self.search.callCount > 0 }
        XCTAssertEqual(search.callCount, 1)
        XCTAssertEqual(search.lastQuery, "abc")
    }

    func testClearSearch_resetsTextAndFilter() async {
        search.stubbedMatches = [UUID()]
        sut.searchText = "milk"
        _ = await waitForDebounce { self.sut.matchedCardIDs != nil }
        sut.clearSearch()
        XCTAssertEqual(sut.searchText, "")
        XCTAssertNil(sut.matchedCardIDs)
    }

    func testAdoptRefreshedMatch_queryMatchesField_adoptsWithoutCallingUseCase() async {
        // A live refresh (store-watcher fire / card edit) now hands the match down from the combined
        // board-view-state read — no second `SearchCards` round-trip (PR #123 r2-1). With a matching
        // live field, the result is adopted directly.
        sut.searchText = "milk"
        _ = await waitForDebounce { self.sut.matchedCardIDs != nil }
        let priorCallCount = search.callCount

        let refreshed: Set<UUID> = [UUID(), UUID()]
        sut.adoptRefreshedMatch(refreshed, for: "milk")

        XCTAssertEqual(sut.matchedCardIDs, refreshed)
        XCTAssertEqual(search.callCount, priorCallCount)  // adopted, not re-fetched
    }

    func testAdoptRefreshedMatch_staleQuery_isIgnored() async {
        // The refresh is async: the user may have typed on between the read starting and landing. A
        // result for the *old* query must not overwrite the field's current filter (PR #123 r2-1).
        let current: Set<UUID> = [UUID()]
        search.stubbedMatches = current
        sut.searchText = "milk"
        _ = await waitForDebounce { self.sut.matchedCardIDs == current }

        // A stale result computed for a no-longer-current query is dropped.
        sut.adoptRefreshedMatch([UUID(), UUID()], for: "different")

        XCTAssertEqual(sut.matchedCardIDs, current)
    }

    func testAdoptRefreshedMatch_blankQueryWhileFieldStillBlank_clearsFilter() async {
        // With a blank live field and a blank-query (nil) refresh, the no-filter sentinel is adopted.
        sut.adoptRefreshedMatch(nil, for: "")
        XCTAssertNil(sut.matchedCardIDs)
    }

    func testIsCardVisible_noFilter_allCardsVisible() {
        XCTAssertTrue(sut.isCardVisible(UUID()))
    }

    func testIsCardVisible_withFilter_onlyMatchedVisible() async {
        let matched = UUID()
        search.stubbedMatches = [matched]
        sut.searchText = "milk"
        _ = await waitForDebounce { self.sut.matchedCardIDs != nil }
        XCTAssertTrue(sut.isCardVisible(matched))
        XCTAssertFalse(sut.isCardVisible(UUID()))
    }
}

/// Configurable `SearchCardsUseCase` double recording the call count and last query, serving a
/// stubbed match set. `@unchecked Sendable` is safe: mutation is on the test's serial @MainActor flow.
final class ConfigurableSearchCards: SearchCardsUseCase, @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var lastQuery: String?
    var stubbedMatches: Set<UUID> = []

    func execute(query: String) async throws -> Set<UUID> {
        callCount += 1
        lastQuery = query
        return stubbedMatches
    }
}
