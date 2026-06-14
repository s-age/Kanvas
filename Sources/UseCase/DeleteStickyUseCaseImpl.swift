final class DeleteStickyUseCaseImpl: AsyncUseCase, Sendable {
    private let stickyService: any StickyServiceProtocol
    private let mapper: BoardResponseMapper

    init(stickyService: any StickyServiceProtocol) {
        self.stickyService = stickyService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteStickyRequest) async throws -> BoardMutationResponse {
        let newState = try await stickyService.delete(id: request.stickyID)
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
