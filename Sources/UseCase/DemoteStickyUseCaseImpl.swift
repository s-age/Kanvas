final class DemoteStickyUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DemoteStickyRequest) async throws -> BoardMutationResponse {
        let newState = try await stickyService.demote(id: request.stickyID)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofSticky: request.stickyID))
    }
}
