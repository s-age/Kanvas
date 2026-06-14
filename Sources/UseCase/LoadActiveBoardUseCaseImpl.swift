final class LoadActiveBoardUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: LoadActiveBoardRequest) async throws -> BoardResponse {
        let state = try await boardManagement.bootstrapActiveBoard()
        return mapper.toBoardResponse(state)
    }
}
