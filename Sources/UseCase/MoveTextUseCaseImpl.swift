final class MoveTextUseCaseImpl: AsyncUseCase, Sendable {
    private let textService: any TextServiceProtocol
    private let mapper: BoardResponseMapper

    init(textService: any TextServiceProtocol) {
        self.textService = textService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: MoveTextRequest) async throws -> BoardMutationResponse {
        let position = CanvasPosition(x: request.positionX, y: request.positionY)
        let newState = try await textService.move(id: request.textID, to: position)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofText: request.textID))
    }
}
