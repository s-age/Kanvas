import Foundation

// The Repository layer's protocol surface, consolidated into one file per layer.

protocol BoardRepositoryProtocol: Sendable {
    // MARK: Active board
    //
    // These operate on the currently-active board. The active board is tracked in the catalog
    // (persisted) and cached in the repository; switching it resets the undo history.

    func loadActiveBoard() async throws -> BoardState
    /// The active board's full state **and** the board catalog (list + active id), read under **one**
    /// exclusive lock — so a refresh can derive the open board, its open card's detail, and the picker
    /// list from a single flock + decode instead of three separate reads (ticket 8DCB811D). Throws
    /// `OperationError.loadFailed` when no catalog / active board exists yet; callers that must
    /// establish one wrap this with bootstrap recovery (see `bootstrapActiveBoardWithCatalog`).
    func loadActiveBoardWithCatalog() async throws -> ActiveBoardSnapshot
    func saveActiveBoard(_ state: BoardState) async throws
    func mutate(_ transform: @Sendable @escaping (BoardState) throws -> BoardState) async throws -> BoardState
    /// Mutates an arbitrary board **by id** — used by the settings window's sidebar, which can edit
    /// any board's settings / column colours. Persists that board's snapshot without switching the
    /// active board. When `id` is the active board the change flows through the cache + undo history
    /// (so it surfaces immediately and is undoable); otherwise the active board is left untouched.
    func mutateBoard(id: UUID,
                     _ transform: @Sendable @escaping (BoardState) throws -> BoardState) async throws -> BoardState
    /// Restores the most recent pre-mutation snapshot of the active board, returning an
    /// `UndoOutcome` that distinguishes the three results the former `BoardState?` collapsed into
    /// one `nil`: `.restored` (the board reverted), `.nothingToUndo` (the ring was empty), and
    /// `.abortedExternalEdit` (the on-disk board diverged from the post-state this process recorded
    /// — a foreign writer, the MCP server, edited it since that mutation — so undo refuses to
    /// clobber that edit and drops the stale ring). The caller distinguishes the latter two to
    /// decide whether to notify the user.
    func undo() async throws -> UndoOutcome

    // MARK: Board catalog

    /// The board catalog — every board (id + title) in display order plus the active id — read under
    /// a single lock so the list and the active id can never be observed mid-update (avoids a
    /// list/active read-then-read race).
    func listBoards() async throws -> BoardCatalog
    /// Loads any board's full state **by id** without switching the active board — used by the
    /// settings window's sidebar to read a non-active board's settings / column colours.
    func loadBoard(id: UUID) async throws -> BoardState
    /// Every board's full state, read under **one** exclusive lock — a single consistent snapshot
    /// across the whole catalog (no cross-board TOCTOU, no per-board active-board reload). Returns
    /// empty `states` when no catalog exists yet.
    ///
    /// **Per-record fail-open** (`arch-repository.md` → "Fail-open per record"): a snapshot that
    /// won't decode (`fileCorrupted`) is *skipped* — its id is returned in `unreadableBoardIDs` and
    /// the skip is logged via `diagnostics` — so one bad file can never brick a caller that only
    /// needs the healthy boards (a board list/picker). An unexpected/transient fault still
    /// propagates (a healthy board is never silently dropped over a blip). The split lets each
    /// caller pick its own policy: a list/picker reads `states` and ignores the rest, while a caller
    /// needing whole-catalog reachability (the orphan-asset GC) treats a non-empty
    /// `unreadableBoardIDs` as "reachability unknown" and aborts. Does not touch the active board's
    /// cache or undo history.
    func loadAllBoardStates() async throws -> (states: [BoardState], unreadableBoardIDs: [UUID])
    /// Switches the active board, returning the target board's full state. Resets undo history.
    func switchActiveBoard(to id: UUID) async throws -> BoardState
    /// Persists a new board and returns it. The mechanism only — save the snapshot, reload the
    /// catalog under the lock, hand it to `resolvingCatalog`, and persist what it returns. The
    /// **domain decisions** — that the new board joins the index and becomes active — belong to
    /// `resolvingCatalog` (a `BoardManagementService` transform), never to this layer; mirrors
    /// `deleteBoard`. Resets undo history.
    func insertBoard(
        _ state: BoardState,
        resolvingCatalog: @Sendable @escaping (BoardCatalog) throws -> BoardCatalog
    ) async throws -> BoardState
    /// Renames a board (any board, not only the active one), returning the updated board list +
    /// active id under one lock. A rename never changes which board is active.
    func renameBoard(id: UUID, title: String) async throws -> (boards: [Board], activeBoardID: UUID?)
    /// Deletes a board and returns the resulting active board's state. The mechanism only —
    /// reload the catalog under the lock, hand it to `resolvingCatalog`, persist the returned
    /// catalog *before* removing the snapshot file (crash-safe ordering), then load the new active
    /// board. The two **domain decisions** — which board becomes active next, and that the last
    /// remaining board may not be deleted — belong to `resolvingCatalog` (a `BoardManagementService`
    /// transform), never to this layer.
    func deleteBoard(
        id: UUID,
        resolvingCatalog: @Sendable @escaping (BoardCatalog) throws -> BoardCatalog
    ) async throws -> BoardState
    /// One-time migration of the legacy single-board file into the catalog layout. Returns the
    /// migrated (now active) board state, or `nil` when there is no legacy file. The mechanism only:
    /// it decodes the legacy snapshot, then hands the decoded board + a fresh empty catalog to
    /// `resolvingCatalog`. The **domain decision** — the migrated board joins the index and becomes
    /// active — belongs to `resolvingCatalog` (the same `BoardManagementService` transform that
    /// backs `insertBoard`); the board is passed in because its id is only known after the decode.
    func migrateLegacyBoard(
        resolvingCatalog: @Sendable @escaping (Board, BoardCatalog) throws -> BoardCatalog
    ) async throws -> BoardState?
    /// Rebuilds a lost or partial catalog from the surviving board snapshots on disk and returns
    /// the resulting active board, or `nil` when no snapshot exists at all (a genuinely empty
    /// store the caller should seed). Used by `bootstrapActiveBoard` so a missing/corrupt
    /// `catalog.json` over surviving `boards/*.json` self-heals instead of seeding a fresh
    /// single-board catalog that orphans every existing board. The mechanism only — list the
    /// surviving snapshots, decode each (fail-open per record), rebuild the board index (prior
    /// order + titles where a snapshot survives, appending any snapshot the prior index no longer
    /// references), then hand that rebuilt index + the prior active hint to `resolvingCatalog` and
    /// persist the returned catalog before loading its active board. The **domain decision** —
    /// which recovered board becomes active (keep the prior active when its snapshot survives, else
    /// promote the first recovered board) — belongs to `resolvingCatalog` (a `BoardManagementService`
    /// transform), never to this layer; mirrors `deleteBoard` / `insertBoard` (the 62FDA087 family).
    /// Resets undo. **Fail-open per record**: an individual snapshot that won't decode is
    /// skipped/dropped + logged (never entering the catalog as a dangling reference) so one bad file
    /// cannot abort the recovery of the healthy boards; returns `nil` only when *no* snapshot can be
    /// loaded at all.
    func recoverOrphanedBoards(
        resolvingCatalog: @Sendable @escaping (BoardCatalog) throws -> BoardCatalog
    ) async throws -> BoardState?

    // MARK: Default template

    /// Loads the app-level Default template — the settings + column blueprint copied into every new
    /// board. Returns `BoardTemplate.default` when none has been persisted yet.
    func loadTemplate() async throws -> BoardTemplate
    /// Persists the Default template. Never touches existing boards — it only shapes future ones.
    func saveTemplate(_ template: BoardTemplate) async throws
}

/// Reads and writes canvas image pixel assets, decoupled from the board snapshot. The board JSON
/// references an asset only by `imageID`; the bytes round-trip through here. A thin pass-through to
/// the Infrastructure store — there is no DTO↔entity conversion (the payload is opaque `Data`).
protocol ImageAssetRepositoryProtocol: Sendable {
    /// Persists the PNG-encoded pixels for `assetID` (the UseCase mints the id alongside the
    /// `CanvasImage` it adds, so the placement and the asset share one identity).
    func save(assetID: UUID, data: Data) async throws
    /// Reads the pixels for `assetID`. Throws when the asset is absent.
    func load(assetID: UUID) async throws -> Data
    /// Removes the asset for `assetID`. A no-op when absent.
    func delete(assetID: UUID) async throws
    /// Ids of every stored asset older than `cutoff` (last-modified strictly before it) — the
    /// orphan GC's candidate set, paired with `now - gracePeriod` so in-flight writes are excluded.
    func assetIDs(modifiedBefore cutoff: Date) async throws -> Set<UUID>
}

/// Reads and writes the durable Markdown autosave journal (ticket 44C9D3C2), decoupled from the
/// board snapshot and its `flock`/undo. A thin DataSource-style pass-through to the Infrastructure
/// store, converting DTO ⇄ `PendingMarkdownEdit`.
protocol MarkdownJournalRepositoryProtocol: Sendable {
    /// Persists (or overwrites) the pending edit for its card — overwrite coalesces to the latest.
    func record(_ edit: PendingMarkdownEdit) async throws
    /// Every journaled pending edit — the startup-restore candidate set.
    func listAll() async throws -> [PendingMarkdownEdit]
    /// Removes the journal entry for `cardID`. A no-op when absent.
    func clear(cardID: UUID) async throws
}
