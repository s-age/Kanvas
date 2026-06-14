final class AddTextUseCaseImpl: AsyncUseCase, Sendable {
    private let textService: any TextServiceProtocol
    private let mapper: BoardResponseMapper

    init(textService: any TextServiceProtocol) {
        self.textService = textService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: AddTextRequest) async throws -> BoardMutationResponse {
        let placement = TextPlacement(
            position: CanvasPosition(x: request.positionX, y: request.positionY),
            size: TextSize(width: request.width, height: request.height)
        )
        let newState = try await textService.add(
            content: request.content, placement: placement, toCardCanvas: request.cardID
        )
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
