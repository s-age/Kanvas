final class ListBoardsUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: ListBoardsRequest) async throws -> BoardListResponse {
        let catalog = try await boardManagement.listBoards()
        return mapper.toBoardListResponse(boards: catalog.boards, activeBoardID: catalog.activeBoardID)
    }
}
