final class AddLabelUseCaseImpl: AsyncUseCase, Sendable {
    private let labelService: any LabelServiceProtocol
    private let mapper: BoardResponseMapper

    init(labelService: any LabelServiceProtocol) {
        self.labelService = labelService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: AddLabelRequest) async throws -> BoardResponse {
        let newState = try await labelService.add(name: request.name, colorHex: request.colorHex)
        return mapper.toBoardResponse(newState)
    }
}
