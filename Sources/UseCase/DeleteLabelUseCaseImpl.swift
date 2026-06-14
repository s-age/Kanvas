final class DeleteLabelUseCaseImpl: AsyncUseCase, Sendable {
    private let labelService: any LabelServiceProtocol
    private let mapper: BoardResponseMapper

    init(labelService: any LabelServiceProtocol) {
        self.labelService = labelService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteLabelRequest) async throws -> BoardResponse {
        let newState = try await labelService.delete(id: request.labelID)
        return mapper.toBoardResponse(newState)
    }
}
