final class SetStickyFillColorUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetStickyFillColorRequest) async throws -> BoardMutationResponse {
        let newState = try await stickyService.setFillColor(id: request.stickyID, fillColorHex: request.fillColorHex)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofSticky: request.stickyID))
    }
}
