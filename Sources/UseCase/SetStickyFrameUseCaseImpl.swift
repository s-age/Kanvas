final class SetStickyFrameUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetStickyFrameRequest) async throws -> BoardMutationResponse {
        let size = StickySize(width: request.width, height: request.height)
        let position = CanvasPosition(x: request.positionX, y: request.positionY)
        let newState = try await stickyService.setFrame(id: request.stickyID, to: size, at: position)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofSticky: request.stickyID))
    }
}
