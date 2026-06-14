final class MoveImageUseCaseImpl: AsyncUseCase, Sendable {
    private let imageService: any CanvasImageServiceProtocol
    private let mapper: BoardResponseMapper

    init(imageService: any CanvasImageServiceProtocol) {
        self.imageService = imageService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: MoveImageRequest) async throws -> BoardMutationResponse {
        let position = CanvasPosition(x: request.positionX, y: request.positionY)
        let newState = try await imageService.move(id: request.imageID, to: position)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofImage: request.imageID))
    }
}
