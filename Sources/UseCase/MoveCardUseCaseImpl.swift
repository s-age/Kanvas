final class MoveCardUseCaseImpl: AsyncUseCase, Sendable {
    private let cardService: any CardServiceProtocol
    private let mapper: BoardResponseMapper

    init(cardService: any CardServiceProtocol) {
        self.cardService = cardService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: MoveCardRequest) async throws -> BoardMutationResponse {
        let newState = try await cardService.move(
            id: request.cardID,
            toColumn: request.toColumnID,
            before: request.beforeCardID
        )
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
