import XCTest
@testable import KanvasCore

/// `CardService.moving` is the single source of truth for translating a semantic
/// "before this card" anchor into concrete `sortIndex` ordering. These tests pin that
/// resolution so a future change to the index math fails loudly instead of silently
/// breaking the Kanban drag-and-drop reorder.
final class CardServiceMovingTests: XCTestCase {

    // Fixed clock so completion-column stamping is deterministic.
    // `static` so the `@Sendable` clock closure captures no (non-Sendable) test instance.
    private static let fixedNow = Date(timeIntervalSince1970: 1_000_000)

    private var service: CardService!

    override func setUp() {
        super.setUp()
        service = CardService(repository: StubBoardRepository(), now: { Self.fixedNow })
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Fixture

    /// Board with two columns:
    /// - A (`columnA`): a0, a1, a2  (sortIndex 0, 1, 2)
    /// - B (`columnB`, completion): b0, b1  (sortIndex 0, 1)
    private struct Fixture {
        let state: BoardState
        let columnA: UUID
        let columnB: UUID
        let a: [UUID]
        let b: [UUID]
    }

    private func makeFixture() -> Fixture {
        let board = Board(title: "Board")
        let columnA = Column(boardID: board.id, title: "A", sortIndex: 0)
        let columnB = Column(boardID: board.id, title: "B", sortIndex: 1, isCompletionColumn: true)
        let a = (0..<3).map { Card(columnID: columnA.id, title: "a\($0)", sortIndex: $0) }
        let b = (0..<2).map { Card(columnID: columnB.id, title: "b\($0)", sortIndex: $0) }
        let state = BoardState(
            board: board,
            columns: [columnA, columnB],
            cards: a + b,
            stickies: []
        )
        return Fixture(
            state: state,
            columnA: columnA.id,
            columnB: columnB.id,
            a: a.map(\.id),
            b: b.map(\.id)
        )
    }

    /// IDs of the cards in `columnID`, ordered by `sortIndex` — the order the UI renders.
    private func order(_ state: BoardState, in columnID: UUID) -> [UUID] {
        state.cards
            .filter { $0.columnID == columnID }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.id)
    }

    // MARK: - moving (same-column reorder)

    func testMoving_forwardWithinSameColumn_placesCardBeforeAnchor() throws {
        let f = makeFixture()

        // Move a2 to before a0.
        let result = try service.moving(id: f.a[2], toColumn: f.columnA, before: f.a[0], in: f.state)

        XCTAssertEqual(order(result, in: f.columnA), [f.a[2], f.a[0], f.a[1]])
    }

    func testMoving_backwardWithinSameColumn_placesCardBeforeAnchor() throws {
        let f = makeFixture()

        // Move a0 to before a2.
        let result = try service.moving(id: f.a[0], toColumn: f.columnA, before: f.a[2], in: f.state)

        XCTAssertEqual(order(result, in: f.columnA), [f.a[1], f.a[0], f.a[2]])
    }

    func testMoving_withinSameColumn_renumbersSortIndexDenselyFromZero() throws {
        let f = makeFixture()

        let result = try service.moving(id: f.a[2], toColumn: f.columnA, before: f.a[0], in: f.state)

        let indices = result.cards.filter { $0.columnID == f.columnA }.map(\.sortIndex).sorted()
        XCTAssertEqual(indices, [0, 1, 2])
    }

    func testMoving_anchorIsMovedCardItself_appendsToEnd() throws {
        let f = makeFixture()

        // The moved card is excluded before the anchor lookup, so its own id is "unknown"
        // as an anchor and the card appends to the end of its column.
        let result = try service.moving(id: f.a[0], toColumn: f.columnA, before: f.a[0], in: f.state)

        XCTAssertEqual(order(result, in: f.columnA), [f.a[1], f.a[2], f.a[0]])
    }

    // MARK: - moving (cross-column)

    func testMoving_toAnotherColumnBeforeAnchor_insertsBeforeAnchorInTarget() throws {
        let f = makeFixture()

        let result = try service.moving(id: f.a[0], toColumn: f.columnB, before: f.b[1], in: f.state)

        XCTAssertEqual(order(result, in: f.columnB), [f.b[0], f.a[0], f.b[1]])
    }

    func testMoving_toAnotherColumn_removesCardFromSourceColumn() throws {
        let f = makeFixture()

        let result = try service.moving(id: f.a[0], toColumn: f.columnB, before: f.b[1], in: f.state)

        XCTAssertEqual(order(result, in: f.columnA), [f.a[1], f.a[2]])
    }

    func testMoving_toAnotherColumn_updatesCardColumnID() throws {
        let f = makeFixture()

        let result = try service.moving(id: f.a[0], toColumn: f.columnB, before: f.b[1], in: f.state)

        XCTAssertEqual(result.cards.first { $0.id == f.a[0] }?.columnID, f.columnB)
    }

    func testMoving_toAnotherColumnWithNilAnchor_appendsToEnd() throws {
        let f = makeFixture()

        let result = try service.moving(id: f.a[0], toColumn: f.columnB, before: nil, in: f.state)

        XCTAssertEqual(order(result, in: f.columnB), [f.b[0], f.b[1], f.a[0]])
    }

    func testMoving_unknownAnchorNotInTargetColumn_appendsToEnd() throws {
        let f = makeFixture()

        // Anchor a1 belongs to column A, not the target column B → treated as unknown → append.
        let result = try service.moving(id: f.a[0], toColumn: f.columnB, before: f.a[1], in: f.state)

        XCTAssertEqual(order(result, in: f.columnB), [f.b[0], f.b[1], f.a[0]])
    }

    // MARK: - moving (completion stamping)

    func testMoving_intoCompletionColumn_stampsCompletedAt() throws {
        let f = makeFixture()

        let result = try service.moving(id: f.a[0], toColumn: f.columnB, before: nil, in: f.state)

        XCTAssertEqual(result.cards.first { $0.id == f.a[0] }?.completedAt, Self.fixedNow)
    }

    func testMoving_outOfCompletionColumn_clearsCompletedAt() throws {
        let f = makeFixture()
        var state = f.state
        let idx = state.cards.firstIndex { $0.id == f.b[0] }!
        state.cards[idx].completedAt = Self.fixedNow

        let result = try service.moving(id: f.b[0], toColumn: f.columnA, before: nil, in: state)

        XCTAssertNil(result.cards.first { $0.id == f.b[0] }?.completedAt)
    }

    // MARK: - moving (guard)

    func testMoving_unknownCardID_throwsNotFound() {
        let f = makeFixture()
        let missingID = UUID()

        XCTAssertThrowsError(try service.moving(id: missingID, toColumn: f.columnB, before: f.b[0], in: f.state)) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Card", id: missingID))
        }
    }
}
