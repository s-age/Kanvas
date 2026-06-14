/// The composition root. Boots the per-layer sub-containers strictly bottom-up
/// (infra → repo → domain → useCases → presentation), each constructed once as a **local** and
/// discarded after wiring. It retains only what the boot layer itself serves: `presentation` (the
/// app scenes' factories) and `useCases` (the MCP gateway). The intermediate containers are gone.
///
/// `Sendable`, not `@MainActor`: `KanvasMCP.makeGateway()` calls `makeMCPGateway()` off the main
/// actor, so the root cannot be main-actor-isolated. The main-actor work lives behind
/// `PresentationContainer` (itself `@MainActor`); `makeBoardViewModel`/`makeSettingsViewModel` hop
/// onto it.
final class Container: Sendable {
    static let shared = Container()

    private let useCases: UseCaseContainer
    private let presentation: PresentationContainer

    private init() {
        let infrastructure = InfrastructureContainer()
        let repositories = RepositoryContainer(infra: infrastructure)
        let domain = DomainContainer(repositories: repositories)
        let useCases = UseCaseContainer(domain: domain)
        // The watcher is Infrastructure; the root is the one layer that may bridge it to the VM.
        // Capture it in a closure so `PresentationContainer` starts live-refresh without naming an
        // Infrastructure type.
        //
        // Lifetime note: the root no longer stores `InfrastructureContainer`, so the watcher's only
        // strong owner is this closure (held by `presentation`, rooted at `Container.shared`). That
        // keeps it alive for the app lifetime as intended — but the lifetime now hangs off the
        // capture. A future refactor that drops or replaces `startStoreWatching` would silently kill
        // live-refresh; keep an owning reference if you change this.
        let boardStoreWatcher = infrastructure.boardStoreWatcher
        self.useCases = useCases
        presentation = PresentationContainer(
            useCases: useCases,
            startStoreWatching: { onChange in boardStoreWatcher.start(onChange: onChange) }
        )
    }

    @MainActor
    func makeBoardViewModel() -> BoardViewModel {
        presentation.makeBoardViewModel()
    }

    @MainActor
    func makeSettingsViewModel(boardViewModel: BoardViewModel) -> SettingsViewModel {
        presentation.makeSettingsViewModel(boardViewModel: boardViewModel)
    }

    /// The MCP server's entry point into the product (see `UseCaseContainer.makeMCPGateway()`).
    /// Internal — reached through the public `KanvasMCP.makeGateway()`.
    func makeMCPGateway() -> KanvasMCPGateway {
        useCases.makeMCPGateway()
    }
}
