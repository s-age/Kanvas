import Foundation

final class InfrastructureContainer: Sendable {
    let boardStore: any BoardStoreProtocol
    let imageAssetStore: any ImageAssetStoreProtocol
    /// Durable Markdown autosave journal — pending edits survive an app quit/crash or a give-up
    /// after repeated failures (ticket 44C9D3C2). Same Application Support root as the board store.
    let markdownJournalStore: any MarkdownJournalStoreProtocol
    /// Notifies when the store directory changes on disk — used to live-refresh the app when the
    /// MCP server (a separate process) edits the same boards. Held as a protocol existential so the
    /// container never exposes the concrete `BoardStoreWatcher` (DI-holds-existentials convention).
    let boardStoreWatcher: any BoardStoreWatcherProtocol
    /// `os.Logger` sink for diagnostics. The Repository `DiagnosticsLogger` adapter wraps this so
    /// the Domain `DiagnosticsLoggingProtocol` port reaches it without `os` leaking upward.
    let diagnostics: any DiagnosticsSinkProtocol

    /// Production entry point — points every store at the shared Application Support root.
    convenience init() {
        self.init(directory: Self.boardStoreDirectory)
    }

    /// Directory-injection seam. The app uses `init()`; tests pass a per-test temp directory so a
    /// suite that builds the real container (e.g. `ValidationWiringTests`) never touches — and on a
    /// failure path never *writes* into — the developer's real board store.
    init(directory: URL) {
        // One ledger shared by the store (records every self-write) and the watcher (skips the
        // self-echo reload our own atomic saves would otherwise trigger — ticket 5BC2FF20).
        let writeLedger = BoardStoreWriteLedger()
        // Built first so the store and watcher can route their silent-degradation failures (decode
        // detail, watcher setup) through it rather than dropping them (ticket 37B774CD).
        let diagnostics = OSDiagnosticsLogger(category: "diagnostics")
        self.diagnostics = diagnostics
        boardStore = JSONBoardStore(directory: directory, writeLedger: writeLedger, diagnostics: diagnostics)
        // Image pixels live under the same Application Support root as the board snapshots
        // (`assets/<imageID>.png`), out-of-band from the board JSON.
        imageAssetStore = FileImageAssetStore(directory: directory)
        // Pending Markdown edits journal alongside the board snapshots (`markdown-journal/<id>.json`).
        // Shares the same diagnostics sink so a corrupt-entry skip / journal-write failure / clear
        // failure surfaces instead of vanishing (ticket 7DA7C85F).
        markdownJournalStore = MarkdownJournalStore(directory: directory, diagnostics: diagnostics)
        boardStoreWatcher = BoardStoreWatcher(directory: directory, writeLedger: writeLedger,
                                              diagnostics: diagnostics)
    }

    /// Resolves the shared Application Support root for the store. Path computation only — creating
    /// the directory (and logging any failure) is the store's job (`JSONBoardStore.init` already
    /// makes the tree before opening its lock), so the DI layer performs no filesystem I/O of its
    /// own and does not duplicate that creation.
    private static var boardStoreDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Kanvas", isDirectory: true)
    }
}
