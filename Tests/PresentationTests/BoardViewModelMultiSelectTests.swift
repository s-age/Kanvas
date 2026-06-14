import Synchronization
import XCTest
@testable import KanvasCore

/// `BoardViewModel`'s multi-selection bookkeeping — the canvas's ⌘-click toggle and marquee
/// region select. The observable contract is `selectedIDs` (the full set the canvas highlights and
/// group move/delete act on); these pin its behaviour independent of how the single/extra buckets
/// are split internally:
/// - a plain single select replaces the whole selection (drops any multi-select).
/// - ⌘-click toggles one id in and out of the set.
/// - a marquee replaces the selection, or unions with it when additive (⌘ held).
/// - a lone id that no longer resolves to a canvas item clears **both** buckets — it never lands
///   as a stray 1-item multi-set (ticket CB849222).
///
/// The selection is one `Set<CanvasSelection>`; `selectedIDs` and the lone `selection` both derive
/// from it. The raw-id entry points (`toggleSelected`/`selectRegion`) classify an id against the
/// open card's detail once, at write time, so the tests open a card whose detail carries the sticky
/// ids they exercise. Collapsing a multi-set to one item needs no re-classification — the survivor
/// keeps the kind it was selected with — so the lone `selection` resolves with no further detail read.
@MainActor
final class BoardViewModelMultiSelectTests: XCTestCase {

    private var mockLoad: ConfigurableLoadCardDetailUseCase!
    private var sut: BoardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockLoad = ConfigurableLoadCardDetailUseCase()
        sut = makeBoardViewModel(loadCardDetail: mockLoad)
    }

    override func tearDown() async throws {
        sut = nil
        mockLoad = nil
        try await super.tearDown()
    }

    /// Opens a card whose detail carries `stickyIDs` and lets the fire-and-forget detail refresh
    /// settle, so `classifySelection` can resolve those ids during the synchronous selection ops.
    private func openCard(stickyIDs: [UUID]) async {
        let cardID = UUID()
        mockLoad.detail = stubCardDetail(id: cardID, stickyIDs: stickyIDs)
        sut.selectCard(id: cardID)
        // The detail load is fire-and-forget; yield until it settles. 50 is a generous upper bound, not
        // a real dependency — the in-memory mock resolves in a single hop. If it never settled the loop
        // would just exit and the test's own assertion would fail (acceptable for a fast unit mock).
        for _ in 0..<50 where sut.selectedCardDetail == nil { await Task.yield() }
    }

    func testSelectedIDs_emptyByDefault() {
        XCTAssertTrue(sut.selectedIDs.isEmpty)
    }

    /// A plain single-select resolves the lone `selection` to its kind **immediately**, before any
    /// card detail has loaded — the kind is recorded at selection time, not re-classified on read.
    /// This pins the no-flicker guarantee that a derive-from-raw-ids `selection` would have broken
    /// (ticket 91292E39): with `selectedCardDetail` still nil, the toolbar must already see a sticky.
    func testSelect_resolvesKindWithoutCardDetail() {
        let id = UUID()

        sut.select(stickyID: id)

        XCTAssertNil(sut.selectedCardDetail)
        XCTAssertEqual(sut.selection, .sticky(id))
    }

    func testSelect_clearsAnyPriorMultiSelection() async {
        let a = UUID(), b = UUID(), c = UUID()
        await openCard(stickyIDs: [a, b, c])
        sut.selectRegion(ids: [a, b], additive: false)

        sut.select(stickyID: c)

        XCTAssertEqual(sut.selectedIDs, [c])
    }

    func testToggleSelected_addsWhenAbsent() async {
        let a = UUID(), b = UUID()
        await openCard(stickyIDs: [a, b])
        sut.selectRegion(ids: [a], additive: false)

        sut.toggleSelected(id: b)

        XCTAssertEqual(sut.selectedIDs, [a, b])
    }

    func testToggleSelected_removesWhenPresent() async {
        let a = UUID(), b = UUID()
        await openCard(stickyIDs: [a, b])
        sut.selectRegion(ids: [a, b], additive: false)

        sut.toggleSelected(id: a)

        XCTAssertEqual(sut.selectedIDs, [b])
    }

    func testSelectRegion_nonAdditive_replacesSelection() async {
        let a = UUID(), b = UUID(), c = UUID()
        await openCard(stickyIDs: [a, b, c])
        sut.selectRegion(ids: [a, b], additive: false)

        sut.selectRegion(ids: [c], additive: false)

        XCTAssertEqual(sut.selectedIDs, [c])
    }

    func testSelectRegion_additive_unionsWithExisting() async {
        let a = UUID(), b = UUID(), c = UUID()
        await openCard(stickyIDs: [a, b, c])
        sut.selectRegion(ids: [a, b], additive: false)

        sut.selectRegion(ids: [c], additive: true)

        XCTAssertEqual(sut.selectedIDs, [a, b, c])
    }

    /// A marquee that catches a single id no longer present in the open card's detail must clear the
    /// whole selection — the buggy fallback left that lone, unresolvable id stranded in the multi-set
    /// (ticket CB849222).
    func testSelectRegion_unresolvedLoneID_clearsBoth() async {
        await openCard(stickyIDs: [])

        sut.selectRegion(ids: [UUID()], additive: false)

        XCTAssertNil(sut.selection)
        XCTAssertTrue(sut.selectedIDs.isEmpty)
    }
}

// MARK: - Fixtures + configurable card-detail loader

private func stubSticky(id: UUID) -> StickyResponse {
    StickyResponse(
        id: id, content: "", isTask: false, linkedCardTitle: nil,
        positionX: 0, positionY: 0, width: 100, height: 80,
        minWidth: 40, minHeight: 40, maxWidth: 400, maxHeight: 400,
        textColorHex: "000000", fontSize: 13, fillColorHex: nil, sortIndex: 0, labels: []
    )
}

private func stubCardDetail(id: UUID, stickyIDs: [UUID]) -> CardDetailResponse {
    CardDetailResponse(
        id: id, title: "Card", markdownContent: "",
        status: .todo, columnTitle: "To Do",
        schedule: nil, labels: [], assignee: nil, prURL: nil, completedAt: nil,
        stickies: stickyIDs.map(stubSticky(id:)), shapes: [], images: [], texts: [], connectors: []
    )
}

/// Returns a settable detail (the card the test opened), so `classifySelection` can resolve the
/// sticky ids the selection ops exercise. Falls back to a bare detail for the requested card.
private final class ConfigurableLoadCardDetailUseCase: LoadCardDetailUseCase, @unchecked Sendable {
    private let stored = Mutex<CardDetailResponse?>(nil)
    var detail: CardDetailResponse? {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }

    func execute(cardID: UUID) async throws -> CardDetailResponse? {
        stored.withLock { $0 } ?? stubCardDetail(id: cardID, stickyIDs: [])
    }
}
