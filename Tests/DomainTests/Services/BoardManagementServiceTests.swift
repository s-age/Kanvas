import XCTest
@testable import KanvasCore

/// The board-catalog **decisions** that used to live in `BoardRepository` and now belong to
/// `BoardManagementService` pure transforms the Repository applies inside its lock: `deletingBoard`
/// (which board becomes active after a delete; the last board may not be deleted),
/// `registeringBoard` (a new board joins the index and becomes active), and `recoveringActiveBoard`
/// (which recovered board becomes active when a lost catalog is rebuilt). The Repository *mechanism*
/// (file ordering, active reload, undo reset) is covered separately by `BoardRepositoryCatalogTests`.
final class BoardManagementServiceTests: XCTestCase {

    private var service: BoardManagementService!

    override func setUp() {
        super.setUp()
        // `deletingBoard` is pure — it never touches the repository — so a stub suffices.
        service = BoardManagementService(
            repository: StubBoardRepository(),
            columnService: ColumnService(repository: StubBoardRepository()),
            diagnostics: SpyDiagnosticsLogger()
        )
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - registeringBoard

    func testRegisteringBoard_appendsItToTheCatalog() {
        let first = Board(title: "First")
        let second = Board(title: "Second")
        let catalog = BoardCatalog(boards: [first], activeBoardID: first.id)

        let next = service.registeringBoard(second, into: catalog)

        XCTAssertEqual(next.boards.map(\.id), [first.id, second.id])
    }

    func testRegisteringBoard_makesItActive() {
        let first = Board(title: "First")
        let second = Board(title: "Second")
        let catalog = BoardCatalog(boards: [first], activeBoardID: first.id)

        let next = service.registeringBoard(second, into: catalog)

        XCTAssertEqual(next.activeBoardID, second.id)
    }

    func testRegisteringBoard_intoEmptyCatalog_seedsItAsTheSoleActiveBoard() {
        // The legacy-migration / first-seed path: a brand-new board into a fresh empty catalog.
        let only = Board(title: "Only")

        let next = service.registeringBoard(only, into: BoardCatalog())

        XCTAssertEqual(next.boards.map(\.id), [only.id])
        XCTAssertEqual(next.activeBoardID, only.id)
    }

    func testRegisteringBoard_alreadyListed_doesNotDuplicateButStillActivates() {
        // Idempotent on the id: re-registering an already-indexed board must not append a second
        // entry, but it still becomes the active board.
        let first = Board(title: "First")
        let second = Board(title: "Second")
        let catalog = BoardCatalog(boards: [first, second], activeBoardID: first.id)

        let next = service.registeringBoard(second, into: catalog)

        XCTAssertEqual(next.boards.map(\.id), [first.id, second.id])
        XCTAssertEqual(next.activeBoardID, second.id)
    }

    // MARK: - deletingBoard

    func testDeletingBoard_removesItFromTheCatalog() throws {
        let first = Board(title: "First")
        let second = Board(title: "Second")
        let catalog = BoardCatalog(boards: [first, second], activeBoardID: first.id)

        let next = try service.deletingBoard(id: second.id, from: catalog)

        XCTAssertEqual(next.boards.map(\.id), [first.id])
    }

    func testDeletingActiveBoard_promotesFirstRemainingToActive() throws {
        let first = Board(title: "First")
        let second = Board(title: "Second")
        // `second` is active and listed second, so removing it must promote `first`.
        let catalog = BoardCatalog(boards: [first, second], activeBoardID: second.id)

        let next = try service.deletingBoard(id: second.id, from: catalog)

        XCTAssertEqual(next.activeBoardID, first.id)
    }

    func testDeletingNonActiveBoard_leavesActiveUnchanged() throws {
        let first = Board(title: "First")
        let second = Board(title: "Second")
        let catalog = BoardCatalog(boards: [first, second], activeBoardID: first.id)

        let next = try service.deletingBoard(id: second.id, from: catalog)

        XCTAssertEqual(next.activeBoardID, first.id)
    }

    func testDeletingLastRemainingBoard_throwsInconsistentState() throws {
        let only = Board(title: "Only")
        let catalog = BoardCatalog(boards: [only], activeBoardID: only.id)

        XCTAssertThrowsError(try service.deletingBoard(id: only.id, from: catalog)) { error in
            XCTAssertEqual(
                error as? OperationError,
                .inconsistentState(reason: "Deleted the last remaining board")
            )
        }
    }

    func testDeletingUnknownBoard_throwsNotFound() throws {
        let first = Board(title: "First")
        let second = Board(title: "Second")
        let catalog = BoardCatalog(boards: [first, second], activeBoardID: first.id)
        let missingID = UUID()

        XCTAssertThrowsError(try service.deletingBoard(id: missingID, from: catalog)) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Board", id: missingID))
        }
    }

    // MARK: - recoveringActiveBoard

    func testRecoveringActiveBoard_priorActiveSurvived_keepsIt() {
        // The Repository pre-sets `activeBoardID` to the prior active when its snapshot survived.
        let first = Board(title: "First")
        let second = Board(title: "Second")
        let catalog = BoardCatalog(boards: [first, second], activeBoardID: second.id)

        let next = service.recoveringActiveBoard(in: catalog)

        XCTAssertEqual(next.activeBoardID, second.id)
    }

    func testRecoveringActiveBoard_priorActiveLost_promotesFirstRecoveredBoard() {
        // The Repository passes `activeBoardID: nil` when the prior active's snapshot did not survive.
        let first = Board(title: "First")
        let second = Board(title: "Second")
        let catalog = BoardCatalog(boards: [first, second], activeBoardID: nil)

        let next = service.recoveringActiveBoard(in: catalog)

        XCTAssertEqual(next.activeBoardID, first.id)
    }

    func testRecoveringActiveBoard_priorActiveNotInRebuiltIndex_promotesFirstRecoveredBoard() {
        // A prior active whose snapshot was present-yet-corrupt is dropped from the rebuilt index, so
        // the hint points at a board no longer listed; recovery must promote the first survivor.
        let first = Board(title: "First")
        let second = Board(title: "Second")
        let droppedActiveID = UUID()
        let catalog = BoardCatalog(boards: [first, second], activeBoardID: droppedActiveID)

        let next = service.recoveringActiveBoard(in: catalog)

        XCTAssertEqual(next.activeBoardID, first.id)
    }
}
