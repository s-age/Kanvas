import Foundation
@testable import KanvasCore

/// The **real** Domain catalog resolvers that drive `BoardRepository.insertBoard` /
/// `migrateLegacyBoard` in repository tests. Each test thus exercises the actual
/// `BoardManagementService` decision ("a new board joins the index and becomes active") rather than
/// a hand-rolled stand-in — the create-side mirror of the `deleting(_:)` helper that wires the real
/// `deletingBoard`. The service is built over throwaway stubs because only its pure transform is
/// used (no repository I/O happens inside `registeringBoard`).
enum BoardCatalogResolvers {
    private static func service() -> BoardManagementService {
        BoardManagementService(
            repository: StubBoardRepository(),
            columnService: ColumnService(repository: StubBoardRepository()),
            diagnostics: SpyDiagnosticsLogger()
        )
    }

    /// Resolver for `insertBoard`: registers `board` and makes it active.
    static func registering(_ board: Board) -> @Sendable (BoardCatalog) throws -> BoardCatalog {
        let service = service()
        return { service.registeringBoard(board, into: $0) }
    }

    /// Resolver for `migrateLegacyBoard`: registers the decoded board (passed in) and makes it active.
    static func migrating() -> @Sendable (Board, BoardCatalog) throws -> BoardCatalog {
        let service = service()
        return { service.registeringBoard($0, into: $1) }
    }

    /// Resolver for `recoverOrphanedBoards`: keeps the prior active board when its snapshot survived,
    /// else promotes the first recovered board.
    static func recovering() -> @Sendable (BoardCatalog) throws -> BoardCatalog {
        let service = service()
        return { service.recoveringActiveBoard(in: $0) }
    }
}

/// Test-only conveniences that wire the canonical domain resolvers automatically, so a repository
/// test focused on insert/migrate **mechanics** (snapshot persisted, undo reset, catalog written)
/// need not restate the resolver at every call site — it still threads the genuine
/// `BoardManagementService` decision via `BoardCatalogResolvers`.
extension BoardRepository {
    func insertBoard(_ state: BoardState) async throws -> BoardState {
        try await insertBoard(state, resolvingCatalog: BoardCatalogResolvers.registering(state.board))
    }

    func migrateLegacyBoard() async throws -> BoardState? {
        try await migrateLegacyBoard(resolvingCatalog: BoardCatalogResolvers.migrating())
    }

    func recoverOrphanedBoards() async throws -> BoardState? {
        try await recoverOrphanedBoards(resolvingCatalog: BoardCatalogResolvers.recovering())
    }
}
