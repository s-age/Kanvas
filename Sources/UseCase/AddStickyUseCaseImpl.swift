final class AddStickyUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: AddStickyRequest) async throws -> BoardMutationResponse {
        let placement = StickyPlacement(
            position: CanvasPosition(x: request.positionX, y: request.positionY),
            size: StickySize(width: request.width, height: request.height),
            fillColorHex: request.fillColorHex
        )
        let newState = try await stickyService.add(
            content: request.content,
            placement: placement,
            toCardCanvas: request.cardID
        )
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
