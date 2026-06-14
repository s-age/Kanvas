final class AddImageUseCaseImpl: AsyncUseCase, Sendable {
    private let imageService: any CanvasImageServiceProtocol
    private let mapper: BoardResponseMapper

    init(imageService: any CanvasImageServiceProtocol) {
        self.imageService = imageService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: AddImageRequest) async throws -> BoardMutationResponse {
        let newState = try await imageService.add(
            imageData: request.imageData,
            naturalSize: NaturalSize(width: request.naturalWidth, height: request.naturalHeight),
            position: CanvasPosition(x: request.positionX, y: request.positionY),
            toCardCanvas: request.cardID
        )
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
