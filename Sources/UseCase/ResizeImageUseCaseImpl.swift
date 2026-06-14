final class ResizeImageUseCaseImpl: AsyncUseCase, Sendable {
    private let imageService: any CanvasImageServiceProtocol
    private let mapper: BoardResponseMapper

    init(imageService: any CanvasImageServiceProtocol) {
        self.imageService = imageService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: ResizeImageRequest) async throws -> BoardMutationResponse {
        let placement = ImagePlacement(
            position: CanvasPosition(x: request.positionX, y: request.positionY),
            size: ImageSize(width: request.width, height: request.height)
        )
        let newState = try await imageService.resize(id: request.imageID, to: placement)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofImage: request.imageID))
    }
}
