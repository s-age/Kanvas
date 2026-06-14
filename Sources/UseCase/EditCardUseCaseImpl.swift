final class EditCardUseCaseImpl: AsyncUseCase, Sendable {
    private let cardService: any CardServiceProtocol
    private let mapper: BoardResponseMapper

    init(cardService: any CardServiceProtocol) {
        self.cardService = cardService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: EditCardRequest) async throws -> BoardMutationResponse {
        let fields = EditCardFields(
            title: request.title?.trimmingCharacters(in: .whitespaces),
            markdownContent: request.markdownContent,
            schedule: request.schedule.map { $0?.toDomain },
            labels: request.labels,
            assignee: request.assignee.map { value in
                let trimmed = value?.trimmingCharacters(in: .whitespaces)
                return (trimmed?.isEmpty ?? true) ? nil : trimmed
            },
            prURL: request.prURL.map { value in
                let trimmed = value?.trimmingCharacters(in: .whitespaces)
                return (trimmed?.isEmpty ?? true) ? nil : trimmed
            }
        )
        let newState = try await cardService.edit(id: request.cardID, fields: fields)
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
