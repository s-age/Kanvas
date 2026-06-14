final class DeleteBoardUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteBoardRequest) async throws -> BoardResponse {
        let state = try await boardManagement.deleteBoard(id: request.boardID)
        return mapper.toBoardResponse(state)
    }
}
