final class BringShapeToFrontUseCaseImpl: AsyncUseCase, Sendable {
    private let shapeService: any ShapeServiceProtocol
    private let mapper: BoardResponseMapper

    init(shapeService: any ShapeServiceProtocol) {
        self.shapeService = shapeService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: BringShapeToFrontRequest) async throws -> BoardMutationResponse {
        let newState = try await shapeService.bringToFront(id: request.shapeID)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofShape: request.shapeID))
    }
}
