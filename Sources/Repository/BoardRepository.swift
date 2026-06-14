import Foundation
import Synchronization

// This repository is split across three same-type files for the `file_length` budget:
//   • `BoardRepository.swift`         — the flock/reload/undo **core**: stored state, `exclusive`,
//                                       `mutate`, `undo`, the active-board reads, and every shared
//                                       helper the other two files reach.
//   • `BoardRepository+Catalog.swift` — board-catalog operations (list / switch / insert / rename /
//                                       delete / migrate-legacy).
//   • `BoardRepository+BoardByID.swift` — edit-any-board-by-id reads/writes, the recovery rebuild,
//                                       and the template pass-throughs.
//
// Splitting forces the shared cache / store / helpers — formerly `private`, sealed to one file —
// up to `internal` so the sibling extensions can reach them: the cross-file extensions could not
// otherwise see a `private`/`fileprivate` member. The widening stays inside `KanvasCore` and is
// inert in practice: every consumer holds `any BoardRepositoryProtocol`, so the protocol existential
// still seals this surface from callers; only direct references to the concrete `BoardRepository`
// (DI wiring + tests, all via `init`) ever see the type, and none touch these members. The members
// kept `private` below are the ones used in this file only. The flock/reload invariant and the undo
// divergence guard (ticket 875C3208) are untouched by the split — only file boundaries moved.

final class BoardRepository: BoardRepositoryProtocol, Sendable {
    /// The working state for one exclusive section, plus the per-process undo ring. **Disk is the
    /// authority**: `exclusive` re-reads `catalog` and `current` from the store at the top of
    /// every operation (the MCP server may have written in between), so neither is a long-lived
    /// cache — they are the in-memory working copy the operation transforms before saving.
    /// `history` is the exception: it persists across reloads (a bounded ring of undo entries,
    /// per-process by design, cleared on a board switch). All live behind one lock so a mutation
    /// records its undo entry atomically with the state change.
    struct CacheState {
        var catalog: BoardCatalog?
        var current: BoardState?
        var history: [UndoEntry] = []
    }

    /// One step in the undo ring: the snapshot to restore (`before`) paired with the post-mutation
    /// snapshot this process wrote (`after`). `undo` restores `before` **only** when the reloaded
    /// disk state still equals `after`; if a foreign writer (the MCP server) edited the board
    /// between this mutation and the undo, `before` would silently clobber that edit — the very
    /// lost-update `mutate`'s reload-inside-lock prevents — so undo aborts instead. See `undo()`.
    struct UndoEntry {
        let before: BoardState
        let after: BoardState
    }

    let store: any BoardStoreProtocol
    let cache: Mutex<CacheState>
    /// The undo depth is a domain policy injected here (`UndoPolicy`), not a number this layer
    /// decides — the Repository only applies the ring bound. See `UndoPolicy`.
    let undoPolicy: UndoPolicy
    /// Observability port for **transport recovery** in `recoverOrphanedBoards` — a per-record
    /// decode failure is skipped/dropped rather than aborting the whole rebuild, and that
    /// degradation must not stay silent (`arch-repository.md` → "Fail-open per record"). Logging
    /// through the injected port keeps the `os` dependency sealed below this layer.
    let diagnostics: any DiagnosticsLoggingProtocol
    /// Keys of snapshot recoveries already logged this process (`boardID|summary|detail`). `exclusive`
    /// re-decodes the active board at the top of *every* operation, and `BoardStoreWatcher` fires
    /// `loadActiveBoard()` on every disk change (~1 s debounce, including the app's own saves), so without
    /// this an unhealed board would re-emit the same `.error` line on every read — drowning the very
    /// signal the logging exists to surface. Log-once-per-(process, board, recovery): the first
    /// occurrence is logged, repeats are suppressed (a later *write* heals the value via the
    /// whole-blob write-back, after which the recovery no longer recurs anyway).
    private let loggedRecoveries: Mutex<Set<String>> = Mutex([])

    init(store: any BoardStoreProtocol, diagnostics: any DiagnosticsLoggingProtocol,
         undoPolicy: UndoPolicy = .default) {
        self.store = store
        self.diagnostics = diagnostics
        self.undoPolicy = undoPolicy
        self.cache = Mutex(CacheState())
    }

    // MARK: - Active board

    func loadActiveBoard() async throws -> BoardState {
        try await exclusive { [self] c in
            // `exclusive` just reloaded `current` from disk; return it. The fallback below only
            // runs when the reload could not produce it (no active board, or a corrupt snapshot)
            // and exists to surface the *right* error rather than a generic one.
            if let current = c.current { return current }
            let catalog = try requireCatalog(&c)
            guard let activeID = catalog.activeBoardID else { throw OperationError.loadFailed }
            let state = try loadState(boardID: activeID, catalog: catalog)
            c.current = state
            return state
        }
    }

    /// The active board's full state **and** the catalog (board list + active id) from **one**
    /// exclusive section — `exclusive` already reloads both catalog + active snapshot under the
    /// flock, so returning them together lets a refresh derive board + open-card detail + picker
    /// list from a single flock + decode instead of three (ticket 8DCB811D). Throws
    /// `OperationError.loadFailed` when no catalog / active board exists yet; the establishing path
    /// is `BoardManagementService.bootstrapActiveBoardWithCatalog`.
    func loadActiveBoardWithCatalog() async throws -> ActiveBoardSnapshot {
        try await exclusive { [self] c in
            let catalog = try requireCatalog(&c)
            guard let activeID = catalog.activeBoardID else { throw OperationError.loadFailed }
            // `exclusive` just reloaded `current` from disk; reuse it (the same decode every other
            // read pays) and only fall back to a fresh `loadState` if the reload could not produce it.
            let state = try c.current ?? loadState(boardID: activeID, catalog: catalog)
            c.current = state
            return ActiveBoardSnapshot(state: state, boards: catalog.boards, activeBoardID: catalog.activeBoardID)
        }
    }

    func saveActiveBoard(_ state: BoardState) async throws {
        try await exclusive { [self] c in
            let boardID = try requireCatalog(&c).activeBoardID ?? state.board.id
            try store.save(boardID: boardID, BoardSnapshotMapper.toDTO(state))
            c.current = state
        }
    }

    func mutate(_ transform: @Sendable @escaping (BoardState) throws -> BoardState) async throws -> BoardState {
        try await exclusive { [self] c in
            let catalog = try requireCatalog(&c)
            guard let activeID = catalog.activeBoardID else { throw OperationError.loadFailed }
            let current = try c.current ?? loadState(boardID: activeID, catalog: catalog)
            let newState = try transform(current)
            try store.save(boardID: activeID, BoardSnapshotMapper.toDTO(newState))
            // Record an undo entry only when the state actually changed — a no-op mutation
            // (e.g. an id that no longer exists) should not consume an undo slot. The entry pairs
            // the pre-image with the post-image so `undo` can detect a foreign write before
            // clobbering it (see `UndoEntry`).
            if newState != current {
                c.history.append(UndoEntry(before: current, after: newState))
                let overflow = c.history.count - undoPolicy.maxDepth
                if overflow > 0 { c.history.removeFirst(overflow) }
            }
            c.current = newState
            return newState
        }
    }

    func undo() async throws -> UndoOutcome {
        try await exclusive { [self] c in
            guard let entry = c.history.popLast() else { return .nothingToUndo }
            let catalog = try requireCatalog(&c)
            let boardID = catalog.activeBoardID ?? entry.before.board.id
            // `exclusive` reloaded `current` from disk. If it no longer equals the post-state this
            // process wrote for this mutation, a foreign writer (the MCP server) edited the board
            // between that mutation and now. Writing `before` back would silently destroy that
            // edit — the lost update `mutate`'s reload-inside-lock exists to prevent. Abort, and
            // drop the whole ring: every older pre-image is equally stale against the diverged
            // disk. The abort is reported as `.abortedExternalEdit` **and logged** — a degradation
            // must not be silent, like this file's other recoveries; the distinct case lets
            // Presentation tell it apart from `.nothingToUndo` and notify the user (ticket D1436DAB).
            // The foreign edit also reaches the app via `BoardStoreWatcher`. (Title is
            // catalog-authoritative and reconciled on load, so a catalog-only rename is not
            // divergence — compare against the
            // reconciled post-state. A missing/corrupt snapshot leaves `current` nil; then we
            // cannot compare and fall through to restore, preserving the prior recovery behaviour.)
            //
            // The comparison relies on `BoardSnapshotMapper` round-tripping a *self-written* state
            // losslessly (`decode(toDTO(x)) == x`, modulo the reconciled title): decode recoveries
            // fire only on malformed DTO fields that `toDTO` never emits. A future lossy/normalizing
            // mapper change would surface here as false-positive aborts — keep that round-trip exact.
            if let onDisk = c.current, onDisk != catalog.reconcilingTitle(of: entry.after) {
                diagnostics.log("undo aborted: active board changed on disk since the mutation",
                                privateDetail: "board=\(boardID)", level: .info)
                c.history.removeAll()
                return .abortedExternalEdit
            }
            try store.save(boardID: boardID, BoardSnapshotMapper.toDTO(entry.before))
            c.current = entry.before
            return .restored(entry.before)
        }
    }

    // MARK: - Shared exclusive section

    /// Runs `body` holding the store's **cross-process** lock, with the catalog + active snapshot
    /// **reloaded from disk first**. The lock alone is not enough: the app and the MCP server each
    /// keep their own `CacheState`, so without re-reading, a stale `current` would be transformed
    /// and saved back — silently clobbering the other process's write (lost update). Every
    /// operation therefore pays a disk round-trip; acceptable at this app's scale, and the price
    /// of multi-process correctness.
    ///
    /// `current` is reloaded (rather than nil-ed) so `mutate`/`mutateBoard` can diff against it
    /// for undo recording. The in-process undo `history` is deliberately preserved across reloads
    /// — it is per-process by design. Note the underlying `flock` is a blocking syscall: while the
    /// other process holds the lock, this parks its (cooperative-pool) thread.
    func exclusive<T: Sendable>(_ body: @Sendable @escaping (inout CacheState) throws -> T) async throws -> T {
        try await store.withExclusiveAccess { [self] in
            try cache.withLock { c in
                c.catalog = nil
                // `try?` on both reads defers a corrupt catalog / missing-or-corrupt active snapshot
                // throw to the method that actually needs it (`requireCatalog` / `c.current ??
                // loadState(...)`). The error type and propagation are unchanged for every existing
                // op — `requireCatalog` rethrows the same `fileCorrupted` — but deferring lets
                // `recoverOrphanedBoards` run its rebuild on a catalog that won't decode.
                if let catalog = try? loadedCatalog(&c), let activeID = catalog.activeBoardID {
                    c.current = try? loadState(boardID: activeID, catalog: catalog)
                } else {
                    c.current = nil
                }
                return try body(&c)
            }
        }
    }

    // MARK: - Catalog helpers

    /// Returns the cached catalog, loading it from the store on first access. Returns `nil` when no
    /// catalog file exists yet (fresh install / pre-migration); other decode errors propagate.
    func loadedCatalog(_ c: inout CacheState) throws -> BoardCatalog? {
        if let catalog = c.catalog { return catalog }
        do {
            let catalog = BoardCatalogMapper.toEntity(try store.loadCatalog())
            c.catalog = catalog
            return catalog
        } catch OperationError.loadFailed {
            return nil
        }
    }

    func requireCatalog(_ c: inout CacheState) throws -> BoardCatalog {
        guard let catalog = try loadedCatalog(&c) else { throw OperationError.loadFailed }
        return catalog
    }

    func persistCatalog(_ catalog: BoardCatalog) throws {
        try store.saveCatalog(BoardCatalogMapper.toDTO(catalog))
    }

    /// Loads a board snapshot and reconciles its title to the catalog. "Which copy of the title is
    /// authoritative" is a domain rule, so the reconciliation itself lives on `BoardCatalog`
    /// (`reconcilingTitle(of:)`); this method only performs the I/O (read the snapshot) and applies
    /// that pure rule. A catalog-only rename therefore surfaces on load without rewriting the
    /// snapshot file, and the snapshot's own `board.title` is never treated as current.
    func loadState(boardID: UUID, catalog: BoardCatalog) throws -> BoardState {
        let state = decodeSnapshot(try store.load(boardID: boardID), boardID: boardID)
        return catalog.reconcilingTitle(of: state)
    }

    /// Decodes a snapshot DTO and **logs every transport recovery** the mapper applied — a discarded
    /// malformed schedule, a dropped dangling connector, a connector field coerced from an unknown
    /// raw value. In this whole-blob store such a recovery is a *latent write* (the next save of any
    /// part of the board persists the coerced/dropped value, with no further decode failure to
    /// observe), so it must be observable, not silent (`arch-repository.md` → "Latent write-back").
    /// The single decode choke point: every `BoardSnapshotMapper.decode` call routes through here.
    /// Each distinct recovery is logged **once per process** (see `loggedRecoveries`) so a re-read of
    /// an unhealed board does not re-emit the same line on every operation.
    func decodeSnapshot(_ dto: BoardSnapshotDTO, boardID: UUID) -> BoardState {
        let (state, recoveries) = BoardSnapshotMapper.decode(dto)
        for recovery in recoveries {
            let key = "\(boardID)|\(recovery.summary)|\(recovery.detail)"
            guard loggedRecoveries.withLock({ $0.insert(key).inserted }) else { continue }
            diagnostics.log("board snapshot recovery: \(recovery.summary)",
                            privateDetail: "board=\(boardID) \(recovery.detail)", level: .error)
        }
        return state
    }
}
