final class DeleteTextUseCaseImpl: AsyncUseCase, Sendable {
    private let textService: any TextServiceProtocol
    private let mapper: BoardResponseMapper

    init(textService: any TextServiceProtocol) {
        self.textService = textService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteTextRequest) async throws -> BoardMutationResponse {
        let newState = try await textService.delete(id: request.textID)
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
