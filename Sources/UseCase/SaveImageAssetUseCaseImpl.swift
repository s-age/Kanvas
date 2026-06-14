import Foundation

/// Persists image bytes as a standalone sidecar asset (no board mutation) and returns its id, for the
/// Markdown editor's drag-drop image import. The board-placing path is `AddImageUseCase`; this one
/// shares the asset store but never touches a `CanvasImage` — the reference lives only as
/// `kanvas-asset://<id>` text in the card's Markdown body.
final class SaveImageAssetUseCaseImpl: AsyncUseCase, Sendable {
    private let imageService: any CanvasImageServiceProtocol

    init(imageService: any CanvasImageServiceProtocol) {
        self.imageService = imageService
    }

    func execute(_ request: SaveImageAssetRequest) async throws -> SaveImageAssetResponse {
        let assetID = try await imageService.saveAsset(imageData: request.imageData)
        return SaveImageAssetResponse(assetID: assetID)
    }
}
