final class MoveShapeUseCaseImpl: AsyncUseCase, Sendable {
    private let shapeService: any ShapeServiceProtocol
    private let mapper: BoardResponseMapper

    init(shapeService: any ShapeServiceProtocol) {
        self.shapeService = shapeService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: MoveShapeRequest) async throws -> BoardMutationResponse {
        let position = CanvasPosition(x: request.positionX, y: request.positionY)
        let newState = try await shapeService.move(id: request.shapeID, to: position)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofShape: request.shapeID))
    }
}
