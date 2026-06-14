/// Owns the Domain service instances. Each Service is "Shape 1": it holds the board repository and
/// owns the `repository.mutate` boundary, so this container takes the `RepositoryContainer`,
/// extracts the protocols it needs (protocol-extraction pattern), and injects them — it never
/// stores the container. `ConnectorService` and `BoardManagementService` additionally compose a
/// sibling Service's pure transforms inside one mutate (the sanctioned multi-entity composition),
/// so those two siblings are constructed first as locals and passed in.
final class DomainContainer: Sendable {
    // Intentionally internal `let` (not `private`): `UseCaseContainer` reads these services in its
    // `init` to inject them into use cases. Do not tighten to `private`.
    let columnService: any ColumnServiceProtocol
    let cardService: any CardServiceProtocol
    let stickyService: any StickyServiceProtocol
    let shapeService: any ShapeServiceProtocol
    let imageService: any CanvasImageServiceProtocol
    let textService: any TextServiceProtocol
    let connectorService: any ConnectorServiceProtocol
    let canvasGroupService: any CanvasGroupServiceProtocol
    let labelService: any LabelServiceProtocol
    let boardManagementService: any BoardManagementServiceProtocol
    let markdownJournalService: any MarkdownJournalServiceProtocol
    /// Pass-through of the Repository diagnostics port (not a Domain Service): the UseCase layer
    /// injects it into use cases that only emit diagnostics (e.g. `ReportImageLoadFailureUseCase`),
    /// mirroring how `RepositoryContainer`/`DomainContainer` surface a capability port (arch-di).
    let diagnostics: any DiagnosticsLoggingProtocol

    init(repositories: RepositoryContainer) {
        let repo = repositories.board
        let imageAssetRepo = repositories.imageAsset

        // Siblings composed by other services are built first as locals so they can be passed in:
        // `ConnectorService` reuses `stickyService`; `CanvasGroupService` reuses all four per-kind
        // services' pure transforms inside one mutate (the sanctioned multi-entity composition).
        let columnService = ColumnService(repository: repo)
        let stickyService = StickyService(repository: repo)
        let shapeService = ShapeService(repository: repo)
        let imageService = CanvasImageService(repository: repo, imageAssetRepository: imageAssetRepo,
                                              diagnostics: repositories.diagnostics)
        let textService = TextService(repository: repo)
        let connectorService = ConnectorService(repository: repo, stickyService: stickyService)
        self.columnService = columnService
        self.stickyService = stickyService
        self.shapeService = shapeService
        self.imageService = imageService
        self.textService = textService
        self.connectorService = connectorService

        cardService = CardService(repository: repo)
        canvasGroupService = CanvasGroupService(repository: repo, stickyService: stickyService,
                                                shapeService: shapeService, imageService: imageService,
                                                textService: textService,
                                                connectorService: connectorService)
        labelService = LabelService(repository: repo)
        boardManagementService = BoardManagementService(repository: repo, columnService: columnService,
                                                        diagnostics: repositories.diagnostics)
        markdownJournalService = MarkdownJournalService(repository: repositories.markdownJournal)
        diagnostics = repositories.diagnostics
    }
}
