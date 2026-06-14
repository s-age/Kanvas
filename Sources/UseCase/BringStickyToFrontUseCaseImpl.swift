final class BringStickyToFrontUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: BringStickyToFrontRequest) async throws -> BoardMutationResponse {
        let newState = try await stickyService.bringToFront(id: request.stickyID)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofSticky: request.stickyID))
    }
}
