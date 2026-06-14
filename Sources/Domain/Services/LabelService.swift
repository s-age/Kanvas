import Foundation

final class LabelService: LabelServiceProtocol, Sendable {
    private let repository: any BoardRepositoryProtocol

    init(repository: any BoardRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: Imperative verbs (own the mutate boundary)
    func add(name: String, colorHex: String) async throws -> BoardState {
        try await repository.mutate { state in self.adding(name: name, colorHex: colorHex, in: state) }
    }

    func edit(id: UUID, name: String, colorHex: String) async throws -> BoardState {
        try await repository.mutate { state in try self.editing(id: id, name: name, colorHex: colorHex, in: state) }
    }

    func delete(id: UUID) async throws -> BoardState {
        try await repository.mutate { state in try self.deleting(id: id, from: state) }
    }

    // MARK: Pure transforms (UNCHANGED)
    func adding(name: String, colorHex: String, in state: BoardState) -> BoardState {
        var state = state
        state.labels.append(StickyLabel(name: normalized(name), colorHex: colorHex))
        return state
    }

    func editing(id: UUID, name: String, colorHex: String, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.labels, entityKind: "Label")
        state.labels[idx].name = normalized(name)
        state.labels[idx].colorHex = colorHex
        return state
    }

    /// Trims surrounding whitespace for storage (validation that the name is non-empty happens in
    /// the Request layer; the transform only normalizes).
    private func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func deleting(id: UUID, from state: BoardState) throws -> BoardState {
        guard state.labels.contains(where: { $0.id == id }) else {
            throw OperationError.notFound(entityKind: "Label", id: id)
        }
        var state = state
        state.labels.removeAll { $0.id == id }
        // Drop dangling references so no sticky keeps a tag for a label that no longer exists.
        for idx in state.stickies.indices {
            state.stickies[idx].labelIDs.removeAll { $0 == id }
        }
        return state
    }
}
