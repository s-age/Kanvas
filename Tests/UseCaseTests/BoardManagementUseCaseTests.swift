import XCTest
@testable import KanvasCore

/// The board-management use cases over the real `BoardRepository` + in-memory store, plus the
/// `LoadActiveBoardUseCaseImpl` bootstrap (migrate legacy / seed default). Each asserts one observable
/// behavior of the Response or resulting board list.
final class BoardManagementUseCaseTests: XCTestCase {

    private var store: InMemoryBoardStore!
    private var repository: BoardRepository!
    private var firstID: UUID!

    override func setUp() {
        super.setUp()
        let first = BoardState.withDefaultColumns(title: "First")
        firstID = first.board.id
        store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(first))
        repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
    }

    override func tearDown() {
        repository = nil
        store = nil
        firstID = nil
        super.tearDown()
    }

    /// The board-management use cases now take a `BoardManagementService` (which owns the
    /// repository) rather than the repository directly. This builds one over the given repository.
    private func boardManagement(_ repo: BoardRepository) -> BoardManagementService {
        BoardManagementService(repository: repo, columnService: ColumnService(repository: repo),
                               diagnostics: SpyDiagnosticsLogger())
    }

    // MARK: - list

    func testListBoards_returnsAllBoardsAndActiveID() async throws {
        let useCase = ListBoardsUseCaseImpl(boardManagement: boardManagement(repository))

        let response = try await useCase.execute(ListBoardsRequest())

        XCTAssertEqual(response.boards.map(\.title), ["First"])
        XCTAssertEqual(response.activeBoardID, firstID)
    }

    // MARK: - add

    func testAddBoard_seedsDefaultColumns() async throws {
        let useCase = AddBoardUseCaseImpl(boardManagement: boardManagement(repository))

        let response = try await useCase.execute(AddBoardRequest(title: "Second"))

        XCTAssertEqual(response.columns.map(\.title), ["To Do", "In Progress", "Done"])
    }

    func testAddBoard_makesNewBoardActive() async throws {
        let useCase = AddBoardUseCaseImpl(boardManagement: boardManagement(repository))

        let response = try await useCase.execute(AddBoardRequest(title: "Second"))

        let catalog = try await repository.listBoards()
        XCTAssertEqual(catalog.activeBoardID, response.board.id)
    }

    func testAddBoard_emptyTitle_throwsValidationError() async throws {
        let useCase = ValidationAsyncUseCaseDecorator(AddBoardUseCaseImpl(boardManagement: boardManagement(repository)))
        do {
            _ = try await useCase.execute(AddBoardRequest(title: "   "))
            XCTFail("Expected emptyTitle")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyTitle)
        }
    }

    // MARK: - switch

    func testSwitchBoard_returnsTargetBoard() async throws {
        let created = try await AddBoardUseCaseImpl(boardManagement: boardManagement(repository))
            .execute(AddBoardRequest(title: "Second"))
        let useCase = SwitchBoardUseCaseImpl(boardManagement: boardManagement(repository))

        let response = try await useCase.execute(SwitchBoardRequest(boardID: firstID))

        XCTAssertEqual(response.board.id, firstID)
        XCTAssertNotEqual(response.board.id, created.board.id)
    }

    // MARK: - rename

    func testRenameBoard_returnsUpdatedListAndActiveID() async throws {
        let useCase = RenameBoardUseCaseImpl(boardManagement: boardManagement(repository))

        let response = try await useCase.execute(RenameBoardRequest(boardID: firstID, title: "Renamed"))

        XCTAssertEqual(response.boards.map(\.title), ["Renamed"])
        XCTAssertEqual(response.activeBoardID, firstID)
    }

    func testRenameBoard_emptyTitle_throwsValidationError() async throws {
        let useCase = ValidationAsyncUseCaseDecorator(RenameBoardUseCaseImpl(boardManagement: boardManagement(repository)))
        do {
            _ = try await useCase.execute(RenameBoardRequest(boardID: firstID, title: " "))
            XCTFail("Expected emptyTitle")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyTitle)
        }
    }

    // MARK: - delete

    func testDeleteBoard_returnsRemainingActiveBoard() async throws {
        let created = try await AddBoardUseCaseImpl(boardManagement: boardManagement(repository))
            .execute(AddBoardRequest(title: "Second"))
        let useCase = DeleteBoardUseCaseImpl(boardManagement: boardManagement(repository))

        let response = try await useCase.execute(DeleteBoardRequest(boardID: created.board.id))

        XCTAssertEqual(response.board.id, firstID)
    }

    // MARK: - LoadActiveBoard bootstrap

    func testLoadActiveBoard_freshInstall_seedsDefaultBoard() async throws {
        let freshRepository = BoardRepository(store: InMemoryBoardStore(), diagnostics: SpyDiagnosticsLogger())
        let useCase = LoadActiveBoardUseCaseImpl(boardManagement: boardManagement(freshRepository))

        let response = try await useCase.execute(LoadActiveBoardRequest())

        XCTAssertEqual(response.columns.map(\.title), ["To Do", "In Progress", "Done"])
    }

    func testLoadActiveBoard_withLegacyFile_migratesLegacyBoard() async throws {
        let legacyStore = InMemoryBoardStore()
        let legacy = BoardState.withDefaultColumns(title: "Legacy")
        legacyStore.legacy = BoardSnapshotMapper.toDTO(legacy)
        let useCase = LoadActiveBoardUseCaseImpl(boardManagement: boardManagement(BoardRepository(store: legacyStore, diagnostics: SpyDiagnosticsLogger())))

        let response = try await useCase.execute(LoadActiveBoardRequest())

        XCTAssertEqual(response.board.id, legacy.board.id)
        XCTAssertEqual(response.board.title, "Legacy")
    }

    /// Regression: a lost/corrupt `catalog.json` over surviving `boards/*.json` must NOT seed a fresh
    /// board (which writes a single-board catalog and orphans the survivors) — it recovers them.
    func testLoadActiveBoard_lostCatalogOverSnapshots_recoversAnExistingBoard() async throws {
        let store = orphanedSnapshotStore(titles: "Kept", "Other")
        let useCase = LoadActiveBoardUseCaseImpl(boardManagement: boardManagement(BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())))

        let response = try await useCase.execute(LoadActiveBoardRequest())

        // The active board is one of the survivors, not a freshly seeded Default board.
        XCTAssertTrue(Set(store.snapshotTitles).contains(response.board.title))
    }

    func testLoadActiveBoard_lostCatalogOverSnapshots_keepsEveryBoardReachable() async throws {
        let store = orphanedSnapshotStore(titles: "Kept", "Other")
        let repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
        let useCase = LoadActiveBoardUseCaseImpl(boardManagement: boardManagement(repository))

        _ = try await useCase.execute(LoadActiveBoardRequest())

        let catalog = try await repository.listBoards()
        XCTAssertEqual(Set(catalog.boards.map(\.title)), ["Kept", "Other"])
    }

    /// Regression: a *corrupt* (undecodable) `catalog.json` over surviving snapshots — which throws
    /// `fileCorrupted`, not `loadFailed` — must also recover, not fail hard or seed over the data.
    func testLoadActiveBoard_corruptCatalogOverSnapshots_recoversInsteadOfFailing() async throws {
        let store = orphanedSnapshotStore(titles: "Kept", "Other")
        store.corruptCatalog = true
        let repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
        let useCase = LoadActiveBoardUseCaseImpl(boardManagement: boardManagement(repository))

        _ = try await useCase.execute(LoadActiveBoardRequest())

        let catalog = try await repository.listBoards()
        XCTAssertEqual(Set(catalog.boards.map(\.title)), ["Kept", "Other"])
    }

    /// Builds a store holding board snapshots with NO catalog — the orphaning-bug scenario.
    private func orphanedSnapshotStore(titles: String...) -> InMemoryBoardStore {
        let store = InMemoryBoardStore()  // empty: no catalog
        for title in titles {
            let board = BoardState.withDefaultColumns(title: title)
            try? store.save(boardID: board.board.id, BoardSnapshotMapper.toDTO(board))
        }
        return store
    }
}
