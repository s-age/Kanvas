final class LoadBoardTemplateUseCaseImpl: LoadBoardTemplateUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute() async throws -> BoardTemplateResponse {
        let template = try await boardManagement.loadTemplate()
        return mapper.toTemplateResponse(template)
    }
}
