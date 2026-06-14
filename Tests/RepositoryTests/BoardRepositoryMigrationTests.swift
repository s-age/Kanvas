import XCTest
@testable import KanvasCore

/// Fresh-install + legacy-migration behavior of `BoardRepository`: with no catalog, reads signal
/// `loadFailed` (the bootstrap trigger), `migrateLegacyBoard` promotes a legacy `board.json`, and
/// `insertBoard` seeds the first board.
final class BoardRepositoryMigrationTests: XCTestCase {

    private var store: InMemoryBoardStore!
    private var diagnostics: SpyDiagnosticsLogger!
    private var repository: BoardRepository!

    override func setUp() {
        super.setUp()
        store = InMemoryBoardStore()  // empty: no catalog, no boards
        diagnostics = SpyDiagnosticsLogger()
        repository = BoardRepository(store: store, diagnostics: diagnostics)
    }

    override func tearDown() {
        repository = nil
        diagnostics = nil
        store = nil
        super.tearDown()
    }

    func testLoadActiveBoard_noCatalog_throwsLoadFailed() async throws {
        do {
            _ = try await repository.loadActiveBoard()
            XCTFail("Expected loadFailed")
        } catch let error as OperationError {
            XCTAssertEqual(error, .loadFailed)
        }
    }

    func testMigrateLegacyBoard_noLegacyFile_returnsNil() async throws {
        let result = try await repository.migrateLegacyBoard()
        XCTAssertNil(result)
    }

    func testMigrateLegacyBoard_promotesLegacyBoardAsActive() async throws {
        let legacy = BoardState.withDefaultColumns(title: "Legacy")
        store.legacy = BoardSnapshotMapper.toDTO(legacy)

        let migrated = try await repository.migrateLegacyBoard()

        XCTAssertEqual(migrated?.board.id, legacy.board.id)
        let activeBoardID = try await repository.listBoards().activeBoardID
        XCTAssertEqual(activeBoardID, legacy.board.id)
        let titles = try await repository.listBoards().boards.map(\.title)
        XCTAssertEqual(titles, ["Legacy"])
    }

    func testInsertBoard_fromEmpty_createsCatalogAndActiveBoard() async throws {
        let seed = BoardState.withDefaultColumns(title: "Seed")

        _ = try await repository.insertBoard(seed)

        let activeBoardID = try await repository.listBoards().activeBoardID
        XCTAssertEqual(activeBoardID, seed.board.id)
        let loadedBoardID = try await repository.loadActiveBoard().board.id
        XCTAssertEqual(loadedBoardID, seed.board.id)
    }

    // MARK: - recoverOrphanedBoards

    func testRecoverOrphanedBoards_emptyStore_returnsNil() async throws {
        // No snapshot on disk → genuinely empty; the caller seeds instead of recovering.
        let result = try await repository.recoverOrphanedBoards()
        XCTAssertNil(result)
    }

    func testRecoverOrphanedBoards_lostCatalog_rebuildsCatalogFromAllSnapshots() async throws {
        // catalog.json gone (empty `InMemoryBoardStore`) but two board snapshots survive on disk.
        let a = BoardState.withDefaultColumns(title: "A")
        let b = BoardState.withDefaultColumns(title: "B")
        try store.save(boardID: a.board.id, BoardSnapshotMapper.toDTO(a))
        try store.save(boardID: b.board.id, BoardSnapshotMapper.toDTO(b))

        _ = try await repository.recoverOrphanedBoards()

        // Both boards remain reachable — neither was orphaned by a fresh single-board catalog.
        let titles = try await repository.listBoards().boards.map(\.title)
        XCTAssertEqual(Set(titles), ["A", "B"])
    }

    func testRecoverOrphanedBoards_corruptCatalog_rebuildsFromAllSnapshots() async throws {
        // catalog.json is present but undecodable (`fileCorrupted`, not absent) while two snapshots
        // survive — the corrupt-index case the reviewer flagged as unhandled.
        let a = BoardState.withDefaultColumns(title: "A")
        let b = BoardState.withDefaultColumns(title: "B")
        try store.save(boardID: a.board.id, BoardSnapshotMapper.toDTO(a))
        try store.save(boardID: b.board.id, BoardSnapshotMapper.toDTO(b))
        store.corruptCatalog = true

        _ = try await repository.recoverOrphanedBoards()

        // A successful recovery rewrote a valid catalog (clearing the corrupt flag) listing both.
        let titles = try await repository.listBoards().boards.map(\.title)
        XCTAssertEqual(Set(titles), ["A", "B"])
    }

    func testRecoverOrphanedBoards_missingActiveSnapshot_promotesSurvivingBoard() async throws {
        // Catalog present and active = A, but A's snapshot is gone while an orphan B survives.
        let a = BoardState.withDefaultColumns(title: "A")
        let store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(a))
        let repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
        let b = BoardState.withDefaultColumns(title: "B")
        try store.save(boardID: b.board.id, BoardSnapshotMapper.toDTO(b))  // orphan, not in catalog
        try store.delete(boardID: a.board.id)                             // active snapshot lost

        let recovered = try await repository.recoverOrphanedBoards()

        XCTAssertEqual(recovered?.board.id, b.board.id)
    }

    func testRecoverOrphanedBoards_missingActiveSnapshot_dropsDanglingBoard() async throws {
        let a = BoardState.withDefaultColumns(title: "A")
        let store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(a))
        let repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
        let b = BoardState.withDefaultColumns(title: "B")
        try store.save(boardID: b.board.id, BoardSnapshotMapper.toDTO(b))
        try store.delete(boardID: a.board.id)

        _ = try await repository.recoverOrphanedBoards()

        // A's snapshot is unrecoverable, so it must not linger as a dangling catalog reference.
        let ids = try await repository.listBoards().boards.map(\.id)
        XCTAssertEqual(ids, [b.board.id])
    }

    // MARK: - recoverOrphanedBoards: per-record fail-open

    func testRecoverOrphanedBoards_corruptOrphanSnapshot_recoversHealthyBoards() async throws {
        // Two orphan snapshots survive but B is present-yet-undecodable. Per-record fail-open: the
        // corrupt one is skipped and the healthy A still recovers — one bad record does not abort
        // the whole rebuild.
        let a = BoardState.withDefaultColumns(title: "A")
        let b = BoardState.withDefaultColumns(title: "B")
        try store.save(boardID: a.board.id, BoardSnapshotMapper.toDTO(a))
        try store.save(boardID: b.board.id, BoardSnapshotMapper.toDTO(b))
        store.corruptBoardIDs = [b.board.id]

        _ = try await repository.recoverOrphanedBoards()

        // B never enters the catalog (so it cannot dangle); A remains reachable.
        let titles = try await repository.listBoards().boards.map(\.title)
        XCTAssertEqual(titles, ["A"])
    }

    func testRecoverOrphanedBoards_corruptOrphanSnapshot_isObservedInDiagnostics() async throws {
        let a = BoardState.withDefaultColumns(title: "A")
        let b = BoardState.withDefaultColumns(title: "B")
        try store.save(boardID: a.board.id, BoardSnapshotMapper.toDTO(a))
        try store.save(boardID: b.board.id, BoardSnapshotMapper.toDTO(b))
        store.corruptBoardIDs = [b.board.id]

        _ = try await repository.recoverOrphanedBoards()

        // The skip is surfaced, not silently swallowed.
        XCTAssertEqual(diagnostics.messages(at: .error).count, 1)
    }

    func testRecoverOrphanedBoards_corruptActiveSnapshot_promotesHealthyBoard() async throws {
        // Catalog present with active = A plus a healthy B; A's snapshot is present but undecodable.
        // Active selection is fail-open — it promotes past the corrupt active to the healthy board.
        let a = BoardState.withDefaultColumns(title: "A")
        let b = BoardState.withDefaultColumns(title: "B")
        let store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(a))
        let repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
        _ = try await repository.insertBoard(b)                     // catalog now A + B (B active)
        _ = try await repository.switchActiveBoard(to: a.board.id)  // A active again
        store.corruptBoardIDs = [a.board.id]                  // A's snapshot now won't decode

        let recovered = try await repository.recoverOrphanedBoards()

        XCTAssertEqual(recovered?.board.id, b.board.id)
    }

    func testRecoverOrphanedBoards_corruptActiveSnapshot_dropsDanglingBoard() async throws {
        let a = BoardState.withDefaultColumns(title: "A")
        let b = BoardState.withDefaultColumns(title: "B")
        let store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(a))
        let repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
        _ = try await repository.insertBoard(b)
        _ = try await repository.switchActiveBoard(to: a.board.id)
        store.corruptBoardIDs = [a.board.id]

        _ = try await repository.recoverOrphanedBoards()

        // The corrupt active is unrecoverable, so it must not linger as a dangling catalog reference.
        let ids = try await repository.listBoards().boards.map(\.id)
        XCTAssertEqual(ids, [b.board.id])
    }

    func testRecoverOrphanedBoards_corruptActiveSnapshot_promotionIsObservedInDiagnostics() async throws {
        let a = BoardState.withDefaultColumns(title: "A")
        let b = BoardState.withDefaultColumns(title: "B")
        let store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(a))
        let diagnostics = SpyDiagnosticsLogger()
        let repository = BoardRepository(store: store, diagnostics: diagnostics)
        _ = try await repository.insertBoard(b)
        _ = try await repository.switchActiveBoard(to: a.board.id)
        store.corruptBoardIDs = [a.board.id]

        _ = try await repository.recoverOrphanedBoards()

        // Dropping the corrupt active before promoting is surfaced.
        XCTAssertEqual(diagnostics.messages(at: .error).count, 1)
    }

    func testRecoverOrphanedBoards_corruptActivePlusSecondCorruptSurvivor_dropsBothDanglingRefs() async throws {
        // Catalog: active = A, plus B and C. A and C are present-yet-undecodable; only B is healthy.
        // Every survivor is load-verified (not just up to the active), so both corrupt boards are
        // dropped — neither lingers in the rebuilt catalog as a dangling reference that would later
        // surface as an `unreadableBoardIDs` entry on the `loadAllBoardStates()` board-list read.
        let a = BoardState.withDefaultColumns(title: "A")
        let b = BoardState.withDefaultColumns(title: "B")
        let c = BoardState.withDefaultColumns(title: "C")
        let store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(a))
        let repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
        _ = try await repository.insertBoard(b)
        _ = try await repository.insertBoard(c)
        _ = try await repository.switchActiveBoard(to: a.board.id)  // A active again
        store.corruptBoardIDs = [a.board.id, c.board.id]

        _ = try await repository.recoverOrphanedBoards()

        // Only the healthy board remains, and the whole-catalog read no longer throws.
        let ids = try await repository.listBoards().boards.map(\.id)
        XCTAssertEqual(ids, [b.board.id])
        let stateTitles = try await repository.loadAllBoardStates().states.map(\.board.title)
        XCTAssertEqual(stateTitles, ["B"])
    }

    func testRecoverOrphanedBoards_transientLoadError_propagatesWithoutDroppingBoard() async throws {
        // A non-decode (transient) read fault must *not* be swallowed as "undecodable" — recovery
        // propagates it (abort + retry next bootstrap) so a healthy board is never dropped from the
        // persisted catalog over a blip. The catch is narrowed to `fileCorrupted` for exactly this.
        let a = BoardState.withDefaultColumns(title: "A")
        try store.save(boardID: a.board.id, BoardSnapshotMapper.toDTO(a))
        store.loadFailingBoardIDs = [a.board.id]

        do {
            _ = try await repository.recoverOrphanedBoards()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OperationError, .loadFailed)
        }
    }

    func testRecoverOrphanedBoards_allSnapshotsCorrupt_returnsNil() async throws {
        // Every surviving snapshot is undecodable → nothing to recover; the caller seeds fresh
        // instead of the rebuild hard-failing.
        let a = BoardState.withDefaultColumns(title: "A")
        try store.save(boardID: a.board.id, BoardSnapshotMapper.toDTO(a))
        store.corruptBoardIDs = [a.board.id]

        let result = try await repository.recoverOrphanedBoards()
        XCTAssertNil(result)
    }
}
