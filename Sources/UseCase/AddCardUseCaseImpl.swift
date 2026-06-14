final class AddCardUseCaseImpl: AsyncUseCase, Sendable {
    private let cardService: any CardServiceProtocol
    private let mapper: BoardResponseMapper

    init(cardService: any CardServiceProtocol) {
        self.cardService = cardService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: AddCardRequest) async throws -> AddCardResponse {
        // Identity is assembled here (not diffed out of the post-state) so the Response can name
        // the created card even when another process appends concurrently.
        let seed = CardSeed(
            title: request.title.trimmingCharacters(in: .whitespaces),
            markdownContent: request.markdownContent
        )
        let newState = try await cardService.add(seed, columnID: request.columnID)
        return AddCardResponse(newCardID: seed.id, board: mapper.toBoardResponse(newState))
    }
}
