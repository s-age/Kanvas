final class SetTextFontSizeUseCaseImpl: AsyncUseCase, Sendable {
    private let textService: any TextServiceProtocol
    private let mapper: BoardResponseMapper

    init(textService: any TextServiceProtocol) {
        self.textService = textService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetTextFontSizeRequest) async throws -> BoardMutationResponse {
        let newState = try await textService.setFontSize(id: request.textID, fontSize: request.fontSize)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofText: request.textID))
    }
}
