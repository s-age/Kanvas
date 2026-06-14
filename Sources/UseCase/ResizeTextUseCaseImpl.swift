final class ResizeTextUseCaseImpl: AsyncUseCase, Sendable {
    private let textService: any TextServiceProtocol
    private let mapper: BoardResponseMapper

    init(textService: any TextServiceProtocol) {
        self.textService = textService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: ResizeTextRequest) async throws -> BoardMutationResponse {
        let placement = TextPlacement(
            position: CanvasPosition(x: request.positionX, y: request.positionY),
            size: TextSize(width: request.width, height: request.height)
        )
        let newState = try await textService.resize(id: request.textID, to: placement)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofText: request.textID))
    }
}
