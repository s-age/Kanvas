import XCTest
@testable import KanvasCore

/// Multi-board behavior of `BoardRepository`: listing, switching (which resets undo), inserting,
/// renaming (catalog-authoritative title), deleting (active vs non-active), and legacy migration.
final class BoardRepositoryCatalogTests: XCTestCase {

    private var store: InMemoryBoardStore!
    private var repository: BoardRepository!
    private var diagnostics: SpyDiagnosticsLogger!
    private var firstID: UUID!

    override func setUp() {
        super.setUp()
        let first = BoardState.withDefaultColumns(title: "First")
        firstID = first.board.id
        store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(first))
        diagnostics = SpyDiagnosticsLogger()
        repository = BoardRepository(store: store, diagnostics: diagnostics)
    }

    override func tearDown() {
        repository = nil
        store = nil
        diagnostics = nil
        firstID = nil
        super.tearDown()
    }

    // MARK: - list / active

    func testListBoards_seededSingleBoard_returnsThatBoard() async throws {
        let catalog = try await repository.listBoards()
        XCTAssertEqual(catalog.boards.map(\.title), ["First"])
    }

    func testActiveBoardID_seededSingleBoard_isThatBoard() async throws {
        let catalog = try await repository.listBoards()
        XCTAssertEqual(catalog.activeBoardID, firstID)
    }

    // MARK: - insert

    func testInsertBoard_makesNewBoardActive() async throws {
        let second = BoardState.withDefaultColumns(title: "Second")

        _ = try await repository.insertBoard(second)

        let catalog = try await repository.listBoards()
        XCTAssertEqual(catalog.activeBoardID, second.board.id)
    }

    func testInsertBoard_appendsToCatalogList() async throws {
        _ = try await repository.insertBoard(BoardState.withDefaultColumns(title: "Second"))

        let catalog = try await repository.listBoards()
        XCTAssertEqual(catalog.boards.map(\.title), ["First", "Second"])
    }

    // MARK: - switch

    func testSwitchActiveBoard_returnsTargetBoardState() async throws {
        let second = BoardState.withDefaultColumns(title: "Second")
        _ = try await repository.insertBoard(second)

        let restored = try await repository.switchActiveBoard(to: firstID)

        XCTAssertEqual(restored.board.id, firstID)
    }

    func testSwitchActiveBoard_clearsUndoHistoryOfPreviousBoard() async throws {
        _ = try await repository.mutate { state in
            var next = state
            next.board.title = "edited"
            return next
        }
        let second = BoardState.withDefaultColumns(title: "Second")
        _ = try await repository.insertBoard(second)

        _ = try await repository.switchActiveBoard(to: firstID)

        // The undo ring is reset on every switch, so nothing is restorable.
        let undone = try await repository.undo()
        XCTAssertEqual(undone, .nothingToUndo)
    }

    // MARK: - rename

    func testRenameBoard_updatesCatalogTitle() async throws {
        _ = try await repository.renameBoard(id: firstID, title: "Renamed")

        let catalog = try await repository.listBoards()
        XCTAssertEqual(catalog.boards.map(\.title), ["Renamed"])
    }

    func testRenameBoard_activeBoard_surfacesOnReload() async throws {
        _ = try await repository.renameBoard(id: firstID, title: "Renamed")

        // The catalog is authoritative for title; a reload reconciles the snapshot to it.
        let second = BoardState.withDefaultColumns(title: "Second")
        _ = try await repository.insertBoard(second)
        let reloaded = try await repository.switchActiveBoard(to: firstID)

        XCTAssertEqual(reloaded.board.title, "Renamed")
    }

    func testRenameBoard_unknownID_throwsNotFound() async throws {
        let unknown = UUID()
        do {
            _ = try await repository.renameBoard(id: unknown, title: "X")
            XCTFail("Expected notFound")
        } catch let error as OperationError {
            XCTAssertEqual(error, .notFound(entityKind: "Board", id: unknown))
        }
    }

    // MARK: - delete

    /// Drives the Repository *mechanism* (catalog-before-file ordering, active reload + undo reset)
    /// with the **real** domain decision: `deleting(_:)` delegates to
    /// `BoardManagementService.deletingBoard` (a pure transform needing no live repository), so a
    /// future change to the production rule can't leave these mechanism tests green on a stale
    /// re-implementation. The decision's own branches are asserted in `BoardManagementServiceTests`.
    private func deleting(_ id: UUID) -> @Sendable (BoardCatalog) throws -> BoardCatalog {
        let service = BoardManagementService(
            repository: StubBoardRepository(),
            columnService: ColumnService(repository: StubBoardRepository()),
            diagnostics: SpyDiagnosticsLogger()
        )
        return { try service.deletingBoard(id: id, from: $0) }
    }

    func testDeleteBoard_active_switchesToRemainingBoard() async throws {
        let second = BoardState.withDefaultColumns(title: "Second")
        _ = try await repository.insertBoard(second)  // second is now active

        let newActive = try await repository.deleteBoard(id: second.board.id, resolvingCatalog: deleting(second.board.id))

        XCTAssertEqual(newActive.board.id, firstID)
        let catalog = try await repository.listBoards()
        XCTAssertEqual(catalog.activeBoardID, firstID)
    }

    func testDeleteBoard_removesItFromCatalog() async throws {
        let second = BoardState.withDefaultColumns(title: "Second")
        _ = try await repository.insertBoard(second)

        _ = try await repository.deleteBoard(id: second.board.id, resolvingCatalog: deleting(second.board.id))

        let catalog = try await repository.listBoards()
        XCTAssertEqual(catalog.boards.map(\.title), ["First"])
    }

    func testDeleteBoard_deletesTheSnapshotFile() async throws {
        let second = BoardState.withDefaultColumns(title: "Second")
        _ = try await repository.insertBoard(second)
        XCTAssertEqual(store.storedBoardCount, 2)

        _ = try await repository.deleteBoard(id: second.board.id, resolvingCatalog: deleting(second.board.id))

        XCTAssertEqual(store.storedBoardCount, 1)
    }

    func testDeleteBoard_nonActive_keepsActiveUnchanged() async throws {
        let second = BoardState.withDefaultColumns(title: "Second")
        _ = try await repository.insertBoard(second)  // second active
        _ = try await repository.switchActiveBoard(to: firstID)  // first active again

        _ = try await repository.deleteBoard(id: second.board.id, resolvingCatalog: deleting(second.board.id))

        let catalog = try await repository.listBoards()
        XCTAssertEqual(catalog.activeBoardID, firstID)
    }

    /// Regression: the catalog reference is persisted before the snapshot file is removed, so a
    /// failure to persist must leave the snapshot intact — never a catalog pointing at a missing
    /// board (a dangling, unrecoverable reference).
    func testDeleteBoard_whenCatalogPersistFails_leavesSnapshotIntact() async throws {
        let second = BoardState.withDefaultColumns(title: "Second")
        _ = try await repository.insertBoard(second)  // two boards, second active
        store.failNextSaveCatalog = true

        do {
            _ = try await repository.deleteBoard(id: second.board.id, resolvingCatalog: deleting(second.board.id))
            XCTFail("expected an error")
        } catch {
        }

        XCTAssertEqual(store.storedBoardCount, 2)
        let catalog = try await repository.listBoards()
        XCTAssertEqual(catalog.boards.count, 2)
    }

    // MARK: - loadAllBoardStates

    func testLoadAllBoardStates_returnsEveryBoardInCatalog() async throws {
        _ = try await repository.insertBoard(BoardState.withDefaultColumns(title: "Second"))

        let result = try await repository.loadAllBoardStates()

        XCTAssertEqual(result.states.map(\.board.title).sorted(), ["First", "Second"])
    }

    func testLoadAllBoardStates_allHealthy_reportsNoUnreadableBoards() async throws {
        _ = try await repository.insertBoard(BoardState.withDefaultColumns(title: "Second"))

        let result = try await repository.loadAllBoardStates()

        XCTAssertEqual(result.unreadableBoardIDs, [])
    }

    func testLoadAllBoardStates_noCatalog_returnsEmpty() async throws {
        let emptyRepository = BoardRepository(store: InMemoryBoardStore(), diagnostics: SpyDiagnosticsLogger())

        let result = try await emptyRepository.loadAllBoardStates()
        XCTAssertEqual(result.states.count, 0)
    }

    func testLoadAllBoardStates_reconcilesTitleToCatalog() async throws {
        // A catalog-only rename must surface here without rewriting the snapshot file — same rule
        // `loadBoard` applies. Rename the active board, then read it back via the bulk path.
        _ = try await repository.renameBoard(id: firstID, title: "Renamed")

        let titles = try await repository.loadAllBoardStates().states.map(\.board.title)

        XCTAssertEqual(titles, ["Renamed"])
    }

    // MARK: - loadAllBoardStates: per-record fail-open

    /// A single corrupt snapshot must not brick the whole board-list read: the healthy boards still
    /// come back in `states`, and the corrupt one is surfaced in `unreadableBoardIDs` (not thrown).
    func testLoadAllBoardStates_oneCorruptSnapshot_returnsHealthyBoardsAndReportsUnreadable() async throws {
        let second = try await repository.insertBoard(BoardState.withDefaultColumns(title: "Second"))
        store.corruptBoardIDs = [second.board.id]

        let result = try await repository.loadAllBoardStates()

        XCTAssertEqual(result.states.map(\.board.title), ["First"])
        XCTAssertEqual(result.unreadableBoardIDs, [second.board.id])
    }

    /// The skip must be observable — never a silent `try?` (`arch-repository.md` → "Fail-open per
    /// record"): a corrupt snapshot is logged at `.error` with the board id in `privateDetail`.
    func testLoadAllBoardStates_oneCorruptSnapshot_logsTheSkip() async throws {
        let second = try await repository.insertBoard(BoardState.withDefaultColumns(title: "Second"))
        store.corruptBoardIDs = [second.board.id]

        _ = try await repository.loadAllBoardStates()

        XCTAssertEqual(diagnostics.messages(at: .error).count, 1)
        XCTAssertTrue(diagnostics.privateDetails(at: .error).contains { $0.contains(second.board.id.uuidString) })
    }

    /// A transient (non-decode) fault is *not* fail-open: it propagates so a healthy board is never
    /// silently dropped over a blip — only `fileCorrupted` is skipped, mirroring `recoverOrphanedBoards`.
    func testLoadAllBoardStates_transientLoadFault_propagates() async throws {
        let second = try await repository.insertBoard(BoardState.withDefaultColumns(title: "Second"))
        store.loadFailingBoardIDs = [second.board.id]

        do {
            _ = try await repository.loadAllBoardStates()
            XCTFail("expected an error")
        } catch {
        }
    }

    // MARK: - loadActiveBoardWithCatalog

    /// The combined single-flock read (ticket 8DCB811D): one `exclusive` returns the active board's
    /// state **and** the catalog (board list + active id) together, so a refresh derives board +
    /// open-card detail + picker list from one decode instead of three. These pin the assembled
    /// `ActiveBoardSnapshot` directly rather than only through the VM spy.
    func testLoadActiveBoardWithCatalog_returnsActiveBoardState() async throws {
        let snapshot = try await repository.loadActiveBoardWithCatalog()
        XCTAssertEqual(snapshot.state.board.id, firstID)
    }

    func testLoadActiveBoardWithCatalog_returnsFullCatalogBoardList() async throws {
        _ = try await repository.insertBoard(BoardState.withDefaultColumns(title: "Second"))

        let snapshot = try await repository.loadActiveBoardWithCatalog()

        XCTAssertEqual(snapshot.boards.map(\.title), ["First", "Second"])
    }

    func testLoadActiveBoardWithCatalog_returnsActiveBoardID() async throws {
        let second = try await repository.insertBoard(BoardState.withDefaultColumns(title: "Second"))

        let snapshot = try await repository.loadActiveBoardWithCatalog()

        XCTAssertEqual(snapshot.activeBoardID, second.board.id)
    }

    /// The returned `state` must be the *active* board's, not some other catalog entry — pins that
    /// the reloaded active snapshot (`c.current`) and `activeBoardID` agree in the one read.
    func testLoadActiveBoardWithCatalog_stateMatchesActiveBoardID() async throws {
        _ = try await repository.insertBoard(BoardState.withDefaultColumns(title: "Second"))

        let snapshot = try await repository.loadActiveBoardWithCatalog()

        XCTAssertEqual(snapshot.state.board.id, snapshot.activeBoardID)
    }

    /// A catalog-only rename is title-authoritative: the combined read must reconcile the active
    /// snapshot's title to the catalog, same as `loadActiveBoard`.
    func testLoadActiveBoardWithCatalog_reconcilesActiveTitleToCatalog() async throws {
        _ = try await repository.renameBoard(id: firstID, title: "Renamed")

        let snapshot = try await repository.loadActiveBoardWithCatalog()

        XCTAssertEqual(snapshot.state.board.title, "Renamed")
    }

    /// No catalog yet (fresh/empty store): the read throws `loadFailed` rather than fabricating an
    /// empty snapshot — establishing the active board is `bootstrapActiveBoardWithCatalog`'s job.
    func testLoadActiveBoardWithCatalog_emptyStore_throwsLoadFailed() async throws {
        let emptyRepository = BoardRepository(store: InMemoryBoardStore(), diagnostics: SpyDiagnosticsLogger())

        do {
            _ = try await emptyRepository.loadActiveBoardWithCatalog()
            XCTFail("Expected loadFailed")
        } catch let error as OperationError {
            XCTAssertEqual(error, .loadFailed)
        }
    }
}
