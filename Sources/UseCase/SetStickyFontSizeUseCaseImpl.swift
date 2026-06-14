final class SetStickyFontSizeUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetStickyFontSizeRequest) async throws -> BoardMutationResponse {
        let newState = try await stickyService.setFontSize(id: request.stickyID, fontSize: request.fontSize)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofSticky: request.stickyID))
    }
}
