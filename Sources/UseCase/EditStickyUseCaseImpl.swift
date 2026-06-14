final class EditStickyUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: EditStickyRequest) async throws -> BoardMutationResponse {
        let newState = try await stickyService.edit(id: request.stickyID, content: request.content)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofSticky: request.stickyID))
    }
}
