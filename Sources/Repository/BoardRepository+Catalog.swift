import Foundation

// MARK: - Board catalog operations
//
// Same-type extension split from `BoardRepository.swift` for the `file_length` budget. Holds the
// board-catalog lifecycle (list / switch / insert / rename / delete / migrate-legacy). Each op runs
// inside `exclusive` (the shared flock + reload-from-disk core) and applies an injected
// `resolvingCatalog` Domain transform for any catalog-shaping *decision* — this layer picks nothing
// itself. Reaches the now-`internal` shared cache/store/helpers in `BoardRepository.swift`.
extension BoardRepository {

    func listBoards() async throws -> BoardCatalog {
        try await exclusive { [self] c in
            try loadedCatalog(&c) ?? BoardCatalog()
        }
    }

    func switchActiveBoard(to id: UUID) async throws -> BoardState {
        try await exclusive { [self] c in
            var catalog = try requireCatalog(&c)
            let state = try loadState(boardID: id, catalog: catalog)
            catalog.activeBoardID = id
            try persistCatalog(catalog)
            c.catalog = catalog
            c.current = state
            c.history = []
            return state
        }
    }

    func insertBoard(
        _ state: BoardState,
        resolvingCatalog: @Sendable @escaping (BoardCatalog) throws -> BoardCatalog
    ) async throws -> BoardState {
        try await exclusive { [self] c in
            let current = try loadedCatalog(&c) ?? BoardCatalog()
            try store.save(boardID: state.board.id, BoardSnapshotMapper.toDTO(state))
            // The resolver appends the board to the index and makes it active — both domain
            // decisions. This layer only supplies the freshly-reloaded catalog and persists the
            // result (mirror of `deleteBoard`).
            let catalog = try resolvingCatalog(current)
            try persistCatalog(catalog)
            c.catalog = catalog
            c.current = state
            c.history = []
            return state
        }
    }

    func renameBoard(id: UUID, title: String) async throws -> (boards: [Board], activeBoardID: UUID?) {
        try await exclusive { [self] c in
            var catalog = try requireCatalog(&c)
            guard let index = catalog.boards.firstIndex(where: { $0.id == id }) else {
                throw OperationError.notFound(entityKind: "Board", id: id)
            }
            catalog.boards[index].title = title
            try persistCatalog(catalog)
            c.catalog = catalog
            if c.current?.board.id == id { c.current?.board.title = title }
            return (catalog.boards, catalog.activeBoardID)
        }
    }

    func deleteBoard(id: UUID, resolvingCatalog: @Sendable @escaping (BoardCatalog) throws -> BoardCatalog)
        async throws -> BoardState {
        try await exclusive { [self] c in
            let current = try requireCatalog(&c)
            // The *decision* — which board becomes active next, and that the last board may not be
            // deleted — is the injected resolver's (a Domain Service transform). This layer supplies
            // the freshly-reloaded catalog and applies whatever the resolver returns; it picks
            // nothing itself.
            let next = try resolvingCatalog(current)
            guard let newActiveID = next.activeBoardID else {
                throw OperationError.inconsistentState(reason: "No active board after deletion")
            }
            // Whether the active board itself was the one deleted is a cache/undo bookkeeping fact
            // (not a domain choice): only then must we reload a different board and reset the undo
            // ring; otherwise the active board and its history are left intact.
            let activeWasDeleted = current.activeBoardID == id

            // Drop the reference FIRST, then delete the file. Persisting the catalog (which no
            // longer references `id`) before removing the snapshot means a failure between the two
            // leaves an orphan file (harmless) rather than a catalog pointing at a missing board
            // (a dangling reference is unrecoverable — the next `loadState` would throw forever).
            if activeWasDeleted {
                let newActive = try loadState(boardID: newActiveID, catalog: next)
                try persistCatalog(next)
                c.catalog = next
                c.current = newActive
                c.history = []
                try store.delete(boardID: id)
                return newActive
            }
            try persistCatalog(next)
            c.catalog = next
            try store.delete(boardID: id)
            return try c.current ?? loadState(boardID: newActiveID, catalog: next)
        }
    }

    func migrateLegacyBoard(
        resolvingCatalog: @Sendable @escaping (Board, BoardCatalog) throws -> BoardCatalog
    ) async throws -> BoardState? {
        try await exclusive { [self] c in
            guard let legacy = try store.loadLegacy() else { return nil }
            let state = decodeSnapshot(legacy, boardID: legacy.board.id)
            try store.save(boardID: state.board.id, BoardSnapshotMapper.toDTO(state))
            // The resolver builds the catalog from the decoded board (registering it + making it
            // active) — the domain decision this layer must not make. A fresh empty catalog is the
            // base: migration runs only when no `catalog.json` exists.
            let catalog = try resolvingCatalog(state.board, BoardCatalog())
            try persistCatalog(catalog)
            c.catalog = catalog
            c.current = state
            c.history = []
            return state
        }
    }
}
