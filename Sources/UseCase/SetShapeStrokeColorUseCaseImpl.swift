final class SetShapeStrokeColorUseCaseImpl: AsyncUseCase, Sendable {
    private let shapeService: any ShapeServiceProtocol
    private let mapper: BoardResponseMapper

    init(shapeService: any ShapeServiceProtocol) {
        self.shapeService = shapeService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetShapeStrokeColorRequest) async throws -> BoardMutationResponse {
        let newState = try await shapeService.setStrokeColor(id: request.shapeID, colorHex: request.colorHex)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofShape: request.shapeID))
    }
}
