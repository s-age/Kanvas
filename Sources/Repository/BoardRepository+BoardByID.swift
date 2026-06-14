import Foundation

// MARK: - Edit any board by id, recovery rebuild, and template pass-throughs
//
// Same-type extension split from `BoardRepository.swift` for the `file_length` budget. Holds the
// by-id reads/writes (`mutateBoard` / `loadBoard` / `loadAllBoardStates`), the lost-catalog
// `recoverOrphanedBoards` rebuild, and the board-template pass-throughs. Reaches the now-`internal`
// shared cache/store/helpers in `BoardRepository.swift`.
extension BoardRepository {

    func mutateBoard(id: UUID,
                     _ transform: @Sendable @escaping (BoardState) throws -> BoardState) async throws -> BoardState {
        try await exclusive { [self] c in
            let catalog = try requireCatalog(&c)
            // Editing the active board routes through the cached state + undo history so the change
            // surfaces immediately and is undoable, exactly like `mutate`.
            if catalog.activeBoardID == id, let current = c.current {
                let newState = try transform(current)
                try store.save(boardID: id, BoardSnapshotMapper.toDTO(newState))
                if newState != current {
                    c.history.append(UndoEntry(before: current, after: newState))
                    let overflow = c.history.count - undoPolicy.maxDepth
                    if overflow > 0 { c.history.removeFirst(overflow) }
                }
                c.current = newState
                return newState
            }
            // A non-active board (or the active board before it is cached): load → transform → save
            // without disturbing the active board's undo history.
            let current = try loadState(boardID: id, catalog: catalog)
            let newState = try transform(current)
            try store.save(boardID: id, BoardSnapshotMapper.toDTO(newState))
            if catalog.activeBoardID == id { c.current = newState }
            return newState
        }
    }

    func loadBoard(id: UUID) async throws -> BoardState {
        try await exclusive { [self] c in
            let catalog = try requireCatalog(&c)
            // Reuse the active board's cached state when it is the one requested; otherwise read the
            // snapshot fresh without disturbing the cache.
            if catalog.activeBoardID == id, let current = c.current { return current }
            return try loadState(boardID: id, catalog: catalog)
        }
    }

    func loadAllBoardStates() async throws -> (states: [BoardState], unreadableBoardIDs: [UUID]) {
        // One lock for the whole catalog — unlike looping `loadBoard(id:)` (each enters `exclusive`,
        // reloading the catalog + active snapshot every time), this reads every board from a single
        // consistent on-disk snapshot. Reuses `loadState` so each board's title is reconciled to the
        // catalog exactly as `loadBoard` does. Does not populate the cache: it is a pure read.
        try await store.withExclusiveAccess { [self] in
            let catalog: BoardCatalog
            do {
                catalog = BoardCatalogMapper.toEntity(try store.loadCatalog())
            } catch OperationError.loadFailed {
                return (states: [], unreadableBoardIDs: [])  // fresh install / pre-migration — nothing to scan
            }
            // **Per-record fail-open**: skip + log a snapshot that won't decode (and surface its id
            // to the caller) rather than throwing the whole list (`arch-repository.md` → "Fail-open
            // per record"). Only `fileCorrupted` is caught — an unexpected/transient fault still
            // propagates so a healthy board is never dropped over a blip, mirroring
            // `recoverOrphanedBoards`.
            var states: [BoardState] = []
            var unreadableBoardIDs: [UUID] = []
            for board in catalog.boards {
                do {
                    states.append(try loadState(boardID: board.id, catalog: catalog))
                } catch OperationError.fileCorrupted {
                    diagnostics.log("loadAllBoardStates skipped a board whose snapshot won't decode",
                                    privateDetail: "board=\(board.id)", level: .error)
                    unreadableBoardIDs.append(board.id)
                }
            }
            return (states: states, unreadableBoardIDs: unreadableBoardIDs)
        }
    }

    func recoverOrphanedBoards(
        resolvingCatalog: @Sendable @escaping (BoardCatalog) throws -> BoardCatalog
    ) async throws -> BoardState? {
        try await exclusive { [self] c in
            let snapshotIDs = try store.listBoardSnapshotIDs()
            // No snapshot on disk → genuinely empty store; let the caller seed a fresh board.
            guard !snapshotIDs.isEmpty else { return nil }
            let surviving = Set(snapshotIDs)

            // Candidate order: prior catalog order first (survivors whose snapshot exists), then any
            // snapshot the prior index no longer references. `try?` folds a missing (`loadFailed`)
            // and a corrupt (`fileCorrupted`) `catalog.json` to "no usable prior index", so a corrupt
            // catalog over healthy snapshots self-heals the same as a missing one.
            let prior = try? loadedCatalog(&c)
            let priorTitles = Dictionary(prior?.boards.map { ($0.id, $0.title) } ?? [],
                                         uniquingKeysWith: { first, _ in first })
            let priorSurvivors = prior?.boards.map(\.id).filter { surviving.contains($0) } ?? []
            let known = Set(priorSurvivors)
            let candidateIDs = priorSurvivors + snapshotIDs.filter { !known.contains($0) }

            // **Per-record fail-open**: load-verify *every* surviving snapshot so a board that won't
            // decode is skipped + logged and never enters the rebuilt index — it cannot linger as a
            // dangling reference, and the remaining healthy boards still recover (`arch-repository.md`
            // → "Fail-open per record"). A prior survivor keeps the catalog-authoritative title (a
            // catalog-only rename outranks the snapshot's); an orphan takes the decoded snapshot's
            // title. Only `fileCorrupted` is caught: an unexpected/transient fault propagates and
            // aborts recovery, so a healthy board is never dropped from the persisted catalog over a
            // blip (it is re-picked on the next bootstrap). Every decoded state is discarded — the
            // chosen active board is reloaded once below, after the resolver picks it — to keep peak
            // memory flat.
            var boards: [Board] = []
            for boardID in candidateIDs {
                let snapshot: BoardState
                do {
                    snapshot = decodeSnapshot(try store.load(boardID: boardID), boardID: boardID)
                } catch OperationError.fileCorrupted {
                    diagnostics.log("recovery skipped a board whose snapshot won't decode",
                                    privateDetail: "board=\(boardID)", level: .error)
                    continue
                }
                boards.append(Board(id: boardID, title: priorTitles[boardID] ?? snapshot.board.title))
            }
            // nil means *no* snapshot decoded, so the caller seeds a fresh board.
            guard !boards.isEmpty else { return nil }

            // The **decision** — which recovered board becomes active — is the injected resolver's
            // (a Domain Service transform), mirroring `deleteBoard` / `insertBoard`. This layer
            // supplies the rebuilt index plus the prior active hint (the prior active id only when
            // its snapshot survives, else nil) and applies whatever the resolver returns; it picks
            // nothing itself.
            let preferredActive = prior?.activeBoardID.flatMap { surviving.contains($0) ? $0 : nil }
            let catalog = try resolvingCatalog(BoardCatalog(boards: boards, activeBoardID: preferredActive))
            guard let activeID = catalog.activeBoardID else {
                throw OperationError.inconsistentState(reason: "No active board after recovery")
            }

            // Load the resolved active board *before* persisting, so a rebuild never leaves a
            // freshly-written catalog pointing at a board that can't load. `loadState` reconciles the
            // active state's title to the rebuilt catalog (a prior catalog-only rename stays
            // authoritative over the snapshot's).
            let state = try loadState(boardID: activeID, catalog: catalog)
            try persistCatalog(catalog)
            c.catalog = catalog
            c.current = state
            c.history = []
            return state
        }
    }

    func loadTemplate() async throws -> BoardTemplate {
        try await store.withExclusiveAccess { [self] in
            guard let dto = try store.loadTemplate() else { return .default }
            return BoardTemplateMapper.toEntity(dto)
        }
    }

    func saveTemplate(_ template: BoardTemplate) async throws {
        try await store.withExclusiveAccess { [self] in
            try store.saveTemplate(BoardTemplateMapper.toDTO(template))
        }
    }
}
