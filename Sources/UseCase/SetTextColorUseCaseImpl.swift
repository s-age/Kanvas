final class SetTextColorUseCaseImpl: AsyncUseCase, Sendable {
    private let textService: any TextServiceProtocol
    private let mapper: BoardResponseMapper

    init(textService: any TextServiceProtocol) {
        self.textService = textService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetTextColorRequest) async throws -> BoardMutationResponse {
        let newState = try await textService.setColor(id: request.textID, colorHex: request.colorHex)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofText: request.textID))
    }
}
