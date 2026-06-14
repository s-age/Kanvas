import Foundation

final class SweepOrphanedImageAssetsUseCaseImpl: SweepOrphanedImageAssetsUseCase, Sendable {
    private let imageService: any CanvasImageServiceProtocol

    init(imageService: any CanvasImageServiceProtocol) {
        self.imageService = imageService
    }

    func execute() async throws {
        // The sweep reads every board snapshot and scans the assets directory — blocking file I/O.
        // That I/O is offloaded inside the store layer (the board store's `flock`+JSON and the asset
        // store's directory scan each run on their own dedicated serial queue via `BlockingIOQueue`),
        // so this `await` suspends the cooperative-pool thread rather than parking it. A previous
        // `Task.detached(priority:)` wrapper here did **not** achieve that — a detached task runs on
        // the same global (cooperative) executor, so it offloaded nothing; the real offload is the
        // dedicated queue below the Repository. Best-effort and idempotent, with no result anyone
        // awaits.
        try await imageService.sweepOrphanedAssets()
    }
}
