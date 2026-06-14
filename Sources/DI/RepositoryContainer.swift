final class RepositoryContainer: Sendable {
    let board: any BoardRepositoryProtocol
    let imageAsset: any ImageAssetRepositoryProtocol
    let markdownJournal: any MarkdownJournalRepositoryProtocol
    /// The diagnostics capability port. This adapter bridges the Domain `DiagnosticsLoggingProtocol`
    /// to the infra `os.Logger` sink; downstream containers inject it where logging is needed.
    let diagnostics: any DiagnosticsLoggingProtocol

    init(infra: InfrastructureContainer) {
        // Build the diagnostics port first: `BoardRepository` consumes it to observe per-record
        // fail-open recovery (`recoverOrphanedBoards`), so it must exist before the board repository.
        let diagnostics = DiagnosticsLogger(sink: infra.diagnostics)
        self.diagnostics = diagnostics
        board = BoardRepository(store: infra.boardStore, diagnostics: diagnostics, undoPolicy: .default)
        imageAsset = ImageAssetRepository(store: infra.imageAssetStore)
        markdownJournal = MarkdownJournalRepository(store: infra.markdownJournalStore)
    }
}
