final class BringImageToFrontUseCaseImpl: AsyncUseCase, Sendable {
    private let imageService: any CanvasImageServiceProtocol
    private let mapper: BoardResponseMapper

    init(imageService: any CanvasImageServiceProtocol) {
        self.imageService = imageService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: BringImageToFrontRequest) async throws -> BoardMutationResponse {
        let newState = try await imageService.bringToFront(id: request.imageID)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofImage: request.imageID))
    }
}
