final class DeleteShapeUseCaseImpl: AsyncUseCase, Sendable {
    private let shapeService: any ShapeServiceProtocol
    private let mapper: BoardResponseMapper

    init(shapeService: any ShapeServiceProtocol) {
        self.shapeService = shapeService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteShapeRequest) async throws -> BoardMutationResponse {
        let newState = try await shapeService.delete(id: request.shapeID)
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
