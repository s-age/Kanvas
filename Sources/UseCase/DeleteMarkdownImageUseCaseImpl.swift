import Foundation

/// Deletes a Markdown inline image from a card. Delegates to `CanvasImageService.deleteMarkdownImage`
/// (removes the first body reference, then reclaims the bytes iff no board still references the asset)
/// and maps the persisted `BoardState` to a `BoardMutationResponse` carrying the affected card's
/// refreshed detail — so the editor / MCP gateway can echo the rewritten body without a disk re-read.
final class DeleteMarkdownImageUseCaseImpl: AsyncUseCase, Sendable {
    private let imageService: any CanvasImageServiceProtocol
    private let mapper: BoardResponseMapper

    init(imageService: any CanvasImageServiceProtocol) {
        self.imageService = imageService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteMarkdownImageRequest) async throws -> BoardMutationResponse {
        let newState = try await imageService.deleteMarkdownImage(
            cardID: request.cardID, assetID: request.assetID
        )
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
