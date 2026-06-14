final class DuplicateTextUseCaseImpl: AsyncUseCase, Sendable {
    private let textService: any TextServiceProtocol
    private let mapper: BoardResponseMapper

    init(textService: any TextServiceProtocol) {
        self.textService = textService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DuplicateTextRequest) async throws -> BoardMutationResponse {
        let position = CanvasPosition(x: request.positionX, y: request.positionY)
        let newState = try await textService.duplicate(id: request.textID, at: position)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofText: request.textID))
    }
}
