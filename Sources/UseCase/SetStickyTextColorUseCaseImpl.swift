final class SetStickyTextColorUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetStickyTextColorRequest) async throws -> BoardMutationResponse {
        let newState = try await stickyService.setTextColor(id: request.stickyID, colorHex: request.colorHex)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofSticky: request.stickyID))
    }
}
