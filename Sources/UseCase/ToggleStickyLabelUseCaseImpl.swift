final class ToggleStickyLabelUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: ToggleStickyLabelRequest) async throws -> BoardMutationResponse {
        let newState = try await stickyService.toggleLabel(stickyID: request.stickyID, labelID: request.labelID)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofSticky: request.stickyID))
    }
}
