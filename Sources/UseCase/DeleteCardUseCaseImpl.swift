final class DeleteCardUseCaseImpl: AsyncUseCase, Sendable {
    private let cardService: any CardServiceProtocol
    private let mapper: BoardResponseMapper

    init(cardService: any CardServiceProtocol) {
        self.cardService = cardService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteCardRequest) async throws -> BoardResponse {
        let newState = try await cardService.delete(id: request.cardID)
        return mapper.toBoardResponse(newState)
    }
}
