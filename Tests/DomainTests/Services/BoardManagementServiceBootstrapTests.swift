import XCTest
@testable import KanvasCore

/// `BoardManagementService.bootstrapActiveBoardWithCatalog()` (ticket 8DCB811D): the establishing
/// front-door for the combined single-read refresh path. The happy path delegates straight to the
/// repository's one-flock `loadActiveBoardWithCatalog`; the cold/corrupt path falls back to the
/// existing `bootstrapActiveBoard` recovery (migrate / recover orphans / seed) and only then reads
/// the now-present catalog — reusing that method keeps the recovery *priority* single-sourced. These
/// exercise the genuinely new branch (the `catch -> bootstrapActiveBoard + boardCatalog` assembly)
/// directly over the real `BoardRepository`, not transitively through the VM spy.
final class BoardManagementServiceBootstrapTests: XCTestCase {

    private func service(over repository: BoardRepository) -> BoardManagementService {
        BoardManagementService(
            repository: repository,
            columnService: ColumnService(repository: repository),
            diagnostics: SpyDiagnosticsLogger()
        )
    }

    // MARK: - happy path (seeded store)

    func testBootstrapActiveBoardWithCatalog_seededStore_returnsActiveBoardState() async throws {
        let first = BoardState.withDefaultColumns(title: "First")
        let store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(first))
        let sut = service(over: BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger()))

        let snapshot = try await sut.bootstrapActiveBoardWithCatalog()

        XCTAssertEqual(snapshot.state.board.id, first.board.id)
    }

    func testBootstrapActiveBoardWithCatalog_seededStore_returnsPopulatedCatalog() async throws {
        let first = BoardState.withDefaultColumns(title: "First")
        let store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(first))
        let sut = service(over: BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger()))

        let snapshot = try await sut.bootstrapActiveBoardWithCatalog()

        XCTAssertEqual(snapshot.boards.map(\.title), ["First"])
    }

    func testBootstrapActiveBoardWithCatalog_seededStore_returnsActiveBoardID() async throws {
        let first = BoardState.withDefaultColumns(title: "First")
        let store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(first))
        let sut = service(over: BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger()))

        let snapshot = try await sut.bootstrapActiveBoardWithCatalog()

        XCTAssertEqual(snapshot.activeBoardID, first.board.id)
    }

    // MARK: - cold store (fresh install -> seed default)

    /// A fresh/empty store has no catalog: the read throws `loadFailed`, the catch seeds a Default
    /// board, and the assembled snapshot carries that board as the active state.
    func testBootstrapActiveBoardWithCatalog_coldStore_seedsAndReturnsActiveState() async throws {
        let repository = BoardRepository(store: InMemoryBoardStore(), diagnostics: SpyDiagnosticsLogger())
        let sut = service(over: repository)

        let snapshot = try await sut.bootstrapActiveBoardWithCatalog()

        XCTAssertEqual(snapshot.state.columns.map(\.title), ["To Do", "In Progress", "Done"])
    }

    /// The post-seed catalog must be populated (one board) and its active id must match the seeded
    /// state — the new method's assembly reads the now-present catalog, never an empty one.
    func testBootstrapActiveBoardWithCatalog_coldStore_returnsPopulatedCatalog() async throws {
        let repository = BoardRepository(store: InMemoryBoardStore(), diagnostics: SpyDiagnosticsLogger())
        let sut = service(over: repository)

        let snapshot = try await sut.bootstrapActiveBoardWithCatalog()

        XCTAssertEqual(snapshot.boards.count, 1)
    }

    func testBootstrapActiveBoardWithCatalog_coldStore_activeIDMatchesSeededState() async throws {
        let repository = BoardRepository(store: InMemoryBoardStore(), diagnostics: SpyDiagnosticsLogger())
        let sut = service(over: repository)

        let snapshot = try await sut.bootstrapActiveBoardWithCatalog()

        XCTAssertEqual(snapshot.activeBoardID, snapshot.state.board.id)
    }

    // MARK: - corrupt catalog over surviving snapshots (recover, don't seed over data)

    /// A corrupt `catalog.json` over surviving snapshots throws `fileCorrupted`; the catch must
    /// *recover* the orphaned boards (not seed a fresh Default that orphans them) and the assembled
    /// catalog must list every survivor.
    func testBootstrapActiveBoardWithCatalog_corruptCatalogOverSnapshots_recoversSurvivors() async throws {
        let store = try orphanedSnapshotStore(titles: "Kept", "Other")
        store.corruptCatalog = true
        let sut = service(over: BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger()))

        let snapshot = try await sut.bootstrapActiveBoardWithCatalog()

        XCTAssertEqual(Set(snapshot.boards.map(\.title)), ["Kept", "Other"])
    }

    func testBootstrapActiveBoardWithCatalog_corruptCatalogOverSnapshots_activeIsASurvivor() async throws {
        let store = try orphanedSnapshotStore(titles: "Kept", "Other")
        store.corruptCatalog = true
        let sut = service(over: BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger()))

        let snapshot = try await sut.bootstrapActiveBoardWithCatalog()

        XCTAssertTrue(Set(store.snapshotTitles).contains(snapshot.state.board.title))
    }

    /// Builds a store holding board snapshots with NO catalog — the orphaned-snapshot scenario.
    private func orphanedSnapshotStore(titles: String...) throws -> InMemoryBoardStore {
        let store = InMemoryBoardStore()  // empty: no catalog
        for title in titles {
            let board = BoardState.withDefaultColumns(title: title)
            try store.save(boardID: board.board.id, BoardSnapshotMapper.toDTO(board))
        }
        return store
    }
}
