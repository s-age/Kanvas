final class UndoUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: UndoRequest) async throws -> UndoResponse {
        UndoResponse(from: try await boardManagement.undo(), mapper: mapper)
    }
}
