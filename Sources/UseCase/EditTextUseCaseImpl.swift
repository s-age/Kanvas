final class EditTextUseCaseImpl: AsyncUseCase, Sendable {
    private let textService: any TextServiceProtocol
    private let mapper: BoardResponseMapper

    init(textService: any TextServiceProtocol) {
        self.textService = textService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: EditTextRequest) async throws -> BoardMutationResponse {
        let newState = try await textService.edit(id: request.textID, content: request.content)
        // An empty-body edit auto-deletes the text (`TextService.editing`), so it may be gone from
        // `newState`; `ownerCardID` then returns nil and the caller falls back to a fresh load.
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofText: request.textID))
    }
}
