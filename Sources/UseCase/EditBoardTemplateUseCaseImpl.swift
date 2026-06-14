final class EditBoardTemplateUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: EditBoardTemplateRequest) async throws -> BoardTemplateResponse {
        let template = request.toDomain()
        try await boardManagement.saveTemplate(template)
        return mapper.toTemplateResponse(template)
    }
}
