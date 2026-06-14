final class LoadBoardByIDUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: LoadBoardByIDRequest) async throws -> BoardResponse {
        let state = try await boardManagement.loadBoard(id: request.boardID)
        return mapper.toBoardResponse(state)
    }
}
