final class DuplicateStickyUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DuplicateStickyRequest) async throws -> BoardMutationResponse {
        let position = CanvasPosition(x: request.positionX, y: request.positionY)
        let newState = try await stickyService.duplicate(id: request.stickyID, at: position)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofSticky: request.stickyID))
    }
}
