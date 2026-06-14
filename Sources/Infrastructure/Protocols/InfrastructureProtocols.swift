import Foundation

// The Infrastructure layer's protocol surface, consolidated into one file per layer.

/// Raw persistence for the multi-board store: a catalog index plus one snapshot file per board.
/// All methods are storage primitives — no board-selection or domain decisions live here (those
/// belong to `BoardRepository`).
///
/// **Invariant — call the synchronous read/write primitives below (`loadCatalog` … `saveTemplate`)
/// ONLY from inside a `withExclusiveAccess` body.** Two reasons, neither type-enforced:
/// 1. *Correctness* — only `withExclusiveAccess` takes the cross-process `flock`; a bare
///    `store.save(...)` would interleave with the other process's read-modify-write and lose an
///    update (the very bug this store exists to prevent).
/// 2. *Concurrency* — these primitives perform **blocking** file I/O. `withExclusiveAccess` runs its
///    body on a dedicated serial queue (off the cooperative pool); calling a primitive outside it
///    would park a cooperative-pool thread on the syscall. `BoardRepository` honours this everywhere.
protocol BoardStoreProtocol: Sendable {
    /// Loads the catalog index. Throws `OperationError.loadFailed` when no catalog exists yet
    /// (fresh install or pre-migration), `OperationError.fileCorrupted` when it won't decode.
    func loadCatalog() throws -> BoardCatalogDTO
    func saveCatalog(_ catalog: BoardCatalogDTO) throws

    /// Loads one board's snapshot. Throws `OperationError.loadFailed` when absent,
    /// `OperationError.fileCorrupted` when it won't decode.
    func load(boardID: UUID) throws -> BoardSnapshotDTO
    func save(boardID: UUID, _ snapshot: BoardSnapshotDTO) throws
    func delete(boardID: UUID) throws

    /// Ids of every persisted board snapshot (`boards/<id>.json`), in a deterministic order.
    /// Returns an empty array when the boards directory does not exist yet (fresh install); files
    /// whose name is not a UUID are skipped. Lets `BoardRepository` tell a genuinely empty store
    /// from a *lost catalog over surviving snapshots*, so a missing `catalog.json` can be rebuilt
    /// from the snapshots rather than orphaning them.
    func listBoardSnapshotIDs() throws -> [UUID]

    /// Reads the pre-multi-board single-file snapshot (`board.json`), or `nil` when absent.
    /// Used once to migrate a legacy single board into the catalog-backed layout.
    func loadLegacy() throws -> BoardSnapshotDTO?

    /// Loads the app-level Default template (`template.json`), or `nil` when none persisted yet.
    /// Throws `OperationError.fileCorrupted` when a file exists but won't decode.
    func loadTemplate() throws -> BoardTemplateDTO?
    func saveTemplate(_ template: BoardTemplateDTO) throws

    /// Runs `body` holding a **cross-process** exclusive lock on the store directory. The caller
    /// (`BoardRepository`) wraps a whole read-modify-write in it so a concurrent process (the app
    /// or the MCP server) cannot interleave its own load→save and lose this one's write. Pure
    /// mechanism — it decides nothing about which operations belong together.
    ///
    /// `async`: the blocking `flock` + JSON I/O runs on a dedicated serial queue (off the
    /// cooperative pool) and the caller suspends — so a slow cross-process lock wait never parks a
    /// cooperative-pool thread. `body` runs on that queue, hence `@Sendable @escaping` + `Sendable`
    /// result.
    func withExclusiveAccess<T: Sendable>(_ body: @Sendable @escaping () throws -> T) async throws -> T
}

/// Watches the board store directory for **external** writes (the `KanvasMCP` server editing the
/// same JSON the app has open) and fires a debounced callback so Presentation can reload. Pure
/// mechanism — it knows nothing about boards; it just reports "the store changed". Held behind this
/// protocol so the DI container passes it as an existential, never the concrete `BoardStoreWatcher`.
protocol BoardStoreWatcherProtocol: Sendable {
    /// Begins watching. `onChange` runs on a private queue, debounced, after any watched directory
    /// changes — **unless** the change is the app's own save (self-echo), filtered by the write
    /// ledger. Calling again replaces the source set (cancelling the previous monitors).
    func start(onChange: @escaping @Sendable () -> Void)
    /// Cancels the monitors and stops firing. Idempotent.
    func stop()
}

/// Lowest-level diagnostics transport — the sink that actually writes to the system log. Consumed
/// only by the Repository adapter `DiagnosticsLogger`, which bridges the Domain
/// `DiagnosticsLoggingProtocol` port to it. Kept distinct from that port so the concrete `os.Logger`
/// dependency (`OSDiagnosticsLogger`) never leaks above Infrastructure.
protocol DiagnosticsSinkProtocol: Sendable {
    /// Writes one message to the underlying log at the given severity. `message` is emitted publicly;
    /// `privateDetail` (if any) is emitted with redacting privacy.
    func emit(_ message: String, privateDetail: String?, level: DiagnosticsLevel)
}

/// Raw persistence for canvas image pixel assets — one file per image, keyed by id, stored
/// out-of-band from the board snapshot so the board JSON stays small. All methods are storage
/// primitives; no domain decisions live here (those belong to `ImageAssetRepository`).
/// All methods are `async`: their blocking file I/O is offloaded to a dedicated serial queue (off
/// the cooperative pool), so a read/write never parks a cooperative-pool thread.
protocol ImageAssetStoreProtocol: Sendable {
    /// Writes (or overwrites) the pixel bytes for `assetID`. The bytes are PNG-encoded by the
    /// caller; this store treats them as opaque.
    func save(assetID: UUID, data: Data) async throws
    /// Reads the pixel bytes for `assetID`. Throws `OperationError.loadFailed` when absent.
    func load(assetID: UUID) async throws -> Data
    /// Removes the asset file. A no-op when absent (so a double-delete is harmless).
    func delete(assetID: UUID) async throws
    /// Ids of every stored asset whose file was last modified strictly before `cutoff`. Backs the
    /// orphan GC: the caller passes `now - gracePeriod`, so an asset written moments ago (e.g. a
    /// concurrent `add` that has not yet committed its `CanvasImage`) is excluded. Returns an empty
    /// set when no assets directory exists yet. Files whose name is not a UUID, or whose
    /// modification date cannot be read, are skipped (never reported as sweepable).
    func assetIDs(modifiedBefore cutoff: Date) async throws -> Set<UUID>
}

/// Raw persistence for the durable Markdown autosave journal — one file per card, keyed by id,
/// stored out-of-band from the board snapshot (ticket 44C9D3C2). All methods are storage
/// primitives; no domain decisions live here (those belong to `MarkdownJournalRepository`).
/// All methods are `async`: their blocking file I/O is offloaded to a dedicated serial queue (off
/// the cooperative pool), so a read/write never parks a cooperative-pool thread.
protocol MarkdownJournalStoreProtocol: Sendable {
    /// Writes (or overwrites) the journal file for `entry.cardID`. Overwrite is the coalescing
    /// mechanism — only the latest unsaved text per card is retained.
    func save(_ entry: MarkdownJournalEntryDTO) async throws
    /// Every stored journal entry. Returns an empty array when no journal directory exists yet; a
    /// malformed/unreadable file is skipped (left in place) and **logged** via the diagnostics sink,
    /// never failing the whole read or vanishing silently. A failure to enumerate the directory at
    /// all is logged and rethrown (the restore is aborted this launch, not recorded as empty).
    func loadAll() async throws -> [MarkdownJournalEntryDTO]
    /// Removes the journal file for `cardID`. A no-op when absent (so a double-delete is harmless).
    func delete(cardID: UUID) async throws
}
