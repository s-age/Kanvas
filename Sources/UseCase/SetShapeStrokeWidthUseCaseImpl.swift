final class SetShapeStrokeWidthUseCaseImpl: AsyncUseCase, Sendable {
    private let shapeService: any ShapeServiceProtocol
    private let mapper: BoardResponseMapper

    init(shapeService: any ShapeServiceProtocol) {
        self.shapeService = shapeService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetShapeStrokeWidthRequest) async throws -> BoardMutationResponse {
        let newState = try await shapeService.setStrokeWidth(id: request.shapeID, width: request.width)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofShape: request.shapeID))
    }
}
