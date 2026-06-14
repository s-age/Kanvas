final class ResizeShapeUseCaseImpl: AsyncUseCase, Sendable {
    private let shapeService: any ShapeServiceProtocol
    private let mapper: BoardResponseMapper

    init(shapeService: any ShapeServiceProtocol) {
        self.shapeService = shapeService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: ResizeShapeRequest) async throws -> BoardMutationResponse {
        let placement = ShapePlacement(
            position: CanvasPosition(x: request.positionX, y: request.positionY),
            size: ShapeSize(width: request.width, height: request.height)
        )
        let newState = try await shapeService.resize(id: request.shapeID, to: placement,
                                               lineRising: request.lineRising)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofShape: request.shapeID))
    }
}
