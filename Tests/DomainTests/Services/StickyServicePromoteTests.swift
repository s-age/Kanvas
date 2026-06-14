import XCTest
@testable import KanvasCore

/// Promotion creates a new card, so it must honour the board's `newCardPosition` placement just
/// like `CardService.adding` — both route through `BoardState.nextCardSortIndex`.
final class StickyServicePromoteTests: XCTestCase {

    private static let fixedNow = Date(timeIntervalSince1970: 2_000_000)
    private var service: StickyService!

    override func setUp() {
        super.setUp()
        service = StickyService(repository: StubBoardRepository(), now: { Self.fixedNow })
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func state(newCardPosition: NewCardPosition) -> (BoardState, Sticky, Column.ID) {
        let board = Board(title: "B")
        let column = Column(boardID: board.id, title: "A", sortIndex: 0)
        let existing = [0, 1, 2].map { Card(columnID: column.id, title: "c\($0)", sortIndex: $0) }
        let sticky = Sticky(cardID: UUID(), content: "free", position: .zero, sortIndex: 0)
        var state = BoardState(board: board, columns: [column], cards: existing, stickies: [sticky])
        state.settings.board = BoardTabSettings(newCardPosition: newCardPosition)
        return (state, sticky, column.id)
    }

    private func promotedCard(_ state: BoardState) -> Card? {
        state.cards.first { $0.title == "free" }
    }

    func testPromoting_newCardPositionBottom_placesAtMaxPlusOne() throws {
        let (state, sticky, columnID) = state(newCardPosition: .bottom)

        let result = try service.promoting(id: sticky.id, toColumn: columnID, in: state)

        XCTAssertEqual(promotedCard(result)?.sortIndex, 3)
    }

    func testPromoting_newCardPositionTop_placesAtMinMinusOne() throws {
        let (state, sticky, columnID) = state(newCardPosition: .top)

        let result = try service.promoting(id: sticky.id, toColumn: columnID, in: state)

        XCTAssertEqual(promotedCard(result)?.sortIndex, -1)
    }

    func testPromoting_stampsCreatedAtFromInjectedClock() throws {
        let (state, sticky, columnID) = state(newCardPosition: .bottom)

        let result = try service.promoting(id: sticky.id, toColumn: columnID, in: state)

        XCTAssertEqual(promotedCard(result)?.createdAt, Self.fixedNow)
    }

    func testPromoting_alreadyTaskSticky_throwsInconsistentState() throws {
        var (state, sticky, columnID) = state(newCardPosition: .bottom)
        // Make the sticky already a task sticky — promoting again must not silently no-op.
        let idx = state.stickies.firstIndex { $0.id == sticky.id }!
        state.stickies[idx].linkedCardID = UUID()

        XCTAssertThrowsError(try service.promoting(id: sticky.id, toColumn: columnID, in: state)) { error in
            guard case .inconsistentState = error as? OperationError else {
                return XCTFail("expected inconsistentState, got \(error)")
            }
        }
    }

    func testPromoting_unknownID_throwsNotFound() {
        let (state, _, columnID) = state(newCardPosition: .bottom)
        let missingID = UUID()

        XCTAssertThrowsError(try service.promoting(id: missingID, toColumn: columnID, in: state)) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Sticky", id: missingID))
        }
    }
}
