import Foundation

final class ColumnService: ColumnServiceProtocol, Sendable {
    private let repository: any BoardRepositoryProtocol
    private let now: @Sendable () -> Date

    init(repository: any BoardRepositoryProtocol, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    // MARK: Imperative verbs (own the mutate boundary)

    func add(title: String) async throws -> BoardState {
        try await repository.mutate { state in self.adding(title: title, boardID: state.board.id, to: state) }
    }

    func rename(id: Column.ID, to title: String) async throws -> BoardState {
        try await repository.mutate { state in try self.renaming(id: id, to: title, in: state) }
    }

    func setCompletion(id: Column.ID, isCompletion: Bool) async throws -> BoardState {
        try await repository.mutate { state in
            try self.settingCompletion(id: id, isCompletion: isCompletion, in: state)
        }
    }

    func reorder(id: Column.ID, before anchorID: Column.ID?) async throws -> BoardState {
        try await repository.mutate { state in try self.reordering(id: id, before: anchorID, in: state) }
    }

    func delete(id: Column.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.deleting(id: id, from: state) }
    }

    // MARK: Pure transforms (UNCHANGED)

    func adding(title: String, boardID: Board.ID, to state: BoardState) -> BoardState {
        var state = state
        let column = Column(boardID: boardID, title: title, sortIndex: state.columns.count)
        state.columns.append(column)
        return state
    }

    func renaming(id: Column.ID, to title: String, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.columns, entityKind: "Column")
        state.columns[idx].title = title
        return state
    }

    func settingColors(id: Column.ID, colors: ColumnColors, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.columns, entityKind: "Column")
        state.columns[idx].headerColorHex = colors.headerColorHex
        state.columns[idx].headerTextColorHex = colors.headerTextColorHex
        state.columns[idx].bodyColorHex = colors.bodyColorHex
        state.columns[idx].headerBorderColorHex = colors.headerBorderColorHex
        state.columns[idx].bodyBorderColorHex = colors.bodyBorderColorHex
        state.columns[idx].indicatorColorHex = colors.indicatorColorHex
        return state
    }

    func settingCompletion(id: Column.ID, isCompletion: Bool, in state: BoardState) throws -> BoardState {
        var state = state
        // Existence check only — the loop below visits every column, so the resolved index is unused.
        _ = try state.requireIndex(of: id, in: \.columns, entityKind: "Column")
        for i in state.columns.indices {
            if state.columns[i].id == id {
                state.columns[i].isCompletionColumn = isCompletion
            } else if isCompletion {
                // At most one completion column per board — clear any previous holder.
                state.columns[i].isCompletionColumn = false
            }
        }
        // Reconcile every card's completedAt against the new flags (single rule on BoardState).
        let stampedAt = now()
        for i in state.cards.indices {
            state.cards[i].completedAt = state.resolvedCompletedAt(
                columnID: state.cards[i].columnID,
                existing: state.cards[i].completedAt,
                now: stampedAt
            )
        }
        return state
    }

    func reordering(id: Column.ID, before anchorID: Column.ID?, in state: BoardState) throws -> BoardState {
        var state = state
        let fromIndex = try state.requireIndex(of: id, in: \.columns, entityKind: "Column")
        let column = state.columns.remove(at: fromIndex)
        let targetIndex: Int
        if let anchorID, let anchorIndex = state.columns.firstIndex(where: { $0.id == anchorID }) {
            targetIndex = anchorIndex
        } else {
            targetIndex = state.columns.count
        }
        guard targetIndex != fromIndex else {
            state.columns.insert(column, at: fromIndex)
            return state
        }
        state.columns.insert(column, at: targetIndex)
        for i in state.columns.indices {
            state.columns[i].sortIndex = i
        }
        return state
    }

    func deleting(id: Column.ID, from state: BoardState) throws -> BoardState {
        guard state.columns.contains(where: { $0.id == id }) else {
            throw OperationError.notFound(entityKind: "Column", id: id)
        }
        let cardIDs = Set(state.cards.filter { $0.columnID == id }.map(\.id))
        // Cascade every card in the column with its whole drill-down subtree: a task sticky on one of
        // these cards links to a sub-card (which lives in another column, so it is *not* in cardIDs),
        // and that sub-card may link further. The shared BoardState helper prunes the transitive
        // closure and all canvas children, mirroring CardService.deleting. Image asset *files* stay
        // on disk for undo-safety (see the helper).
        var state = state.deletingCardSubtrees(rootCardIDs: cardIDs)
        state.columns.removeAll { $0.id == id }
        for i in state.columns.indices {
            state.columns[i].sortIndex = i
        }
        return state
    }
}
