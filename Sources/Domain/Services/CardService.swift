import Foundation

final class CardService: CardServiceProtocol, Sendable {
    private let repository: any BoardRepositoryProtocol
    private let now: @Sendable () -> Date

    init(repository: any BoardRepositoryProtocol, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    // MARK: Imperative verbs (own the mutate boundary)

    func add(_ seed: CardSeed, columnID: Column.ID) async throws -> BoardState {
        try await repository.mutate { state in self.adding(seed, columnID: columnID, to: state) }
    }

    func edit(id: Card.ID, fields: EditCardFields) async throws -> BoardState {
        try await repository.mutate { state in try self.editing(id: id, fields: fields, in: state) }
    }

    func move(id: Card.ID, toColumn: Column.ID, before: Card.ID?) async throws -> BoardState {
        try await repository.mutate { state in try self.moving(id: id, toColumn: toColumn, before: before, in: state) }
    }

    func delete(id: Card.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.deleting(id: id, from: state) }
    }

    // MARK: Pure transforms

    func adding(_ seed: CardSeed, columnID: Column.ID, to state: BoardState) -> BoardState {
        var state = state
        let card = Card(
            id: seed.id,
            columnID: columnID,
            title: seed.title,
            markdownContent: seed.markdownContent ?? "",
            completedAt: state.resolvedCompletedAt(columnID: columnID, existing: nil, now: now()),
            createdAt: now(),
            sortIndex: state.nextCardSortIndex(inColumn: columnID)
        )
        state.cards.append(card)
        return state
    }

    func editing(id: Card.ID, fields: EditCardFields, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.cards, entityKind: "Card")
        if let title = fields.title { state.cards[idx].title = title }
        if let markdownContent = fields.markdownContent { state.cards[idx].markdownContent = markdownContent }
        if let schedule = fields.schedule { state.cards[idx].schedule = schedule }
        if let labels = fields.labels { state.cards[idx].labels = labels }
        if let assignee = fields.assignee { state.cards[idx].assignee = assignee }
        if let prURL = fields.prURL { state.cards[idx].prURL = prURL }
        return state
    }

    func moving(id: Card.ID, toColumn: Column.ID, before: Card.ID?, in state: BoardState) throws -> BoardState {
        var state = state
        let cardIdx = try state.requireIndex(of: id, in: \.cards, entityKind: "Card")

        state.cards[cardIdx].columnID = toColumn
        state.cards[cardIdx].completedAt = state.resolvedCompletedAt(
            columnID: toColumn,
            existing: state.cards[cardIdx].completedAt,
            now: now()
        )

        var targetCards = state.cards
            .enumerated()
            .filter { $0.element.columnID == toColumn && $0.element.id != id }
            .sorted { $0.element.sortIndex < $1.element.sortIndex }

        // Resolve the semantic "before this card" anchor into a concrete insertion index
        // against the target column with the moved card already excluded. A nil or unknown
        // anchor (the card is not in this column) appends to the end.
        let insertIndex = before
            .flatMap { anchor in targetCards.firstIndex { $0.element.id == anchor } }
            ?? targetCards.count

        let movedEntry = (offset: cardIdx, element: state.cards[cardIdx])
        targetCards.insert(movedEntry, at: insertIndex)

        for (sortIdx, entry) in targetCards.enumerated() {
            state.cards[entry.offset].sortIndex = sortIdx
        }
        return state
    }

    func deleting(id: Card.ID, from state: BoardState) throws -> BoardState {
        guard state.cards.contains(where: { $0.id == id }) else {
            throw OperationError.notFound(entityKind: "Card", id: id)
        }
        // Delete the card and its entire drill-down subtree: a task sticky on this card's canvas
        // links to a sub-card whose own canvas may link further, so pruning only the direct children
        // would strand the nested cards (and their canvases) as orphans. The shared recursive helper
        // on BoardState removes every child kind — stickies / shapes / images / texts / connectors —
        // across the whole closure. Image asset *files* stay on disk for undo-safety (see helper).
        return state.deletingCardSubtrees(rootCardIDs: [id])
    }
}
