final class DeleteImageUseCaseImpl: AsyncUseCase, Sendable {
    private let imageService: any CanvasImageServiceProtocol
    private let mapper: BoardResponseMapper

    init(imageService: any CanvasImageServiceProtocol) {
        self.imageService = imageService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteImageRequest) async throws -> BoardMutationResponse {
        // Removes only the canvas item; the sidecar asset is left in place so an undo can restore
        // the image (and orphaned assets are harmless).
        let newState = try await imageService.delete(id: request.imageID)
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
