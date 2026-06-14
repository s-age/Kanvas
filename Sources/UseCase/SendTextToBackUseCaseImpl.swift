final class SendTextToBackUseCaseImpl: AsyncUseCase, Sendable {
    private let textService: any TextServiceProtocol
    private let mapper: BoardResponseMapper

    init(textService: any TextServiceProtocol) {
        self.textService = textService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SendTextToBackRequest) async throws -> BoardMutationResponse {
        let newState = try await textService.sendToBack(id: request.textID)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofText: request.textID))
    }
}
