/// The Presentation-facing result of an undo — a 1:1 mirror of the Domain `UndoOutcome` so
/// Presentation never sees the Domain enum directly (the mirroring is the load-bearing
/// Domain/Presentation boundary; see `arch-usecase.md` → "Domain events as Response"). The two
/// non-restoring cases carry no payload: Presentation assembles any user-facing wording locally.
enum UndoResponse: Sendable, Equatable {
    /// The board reverted to the restored snapshot.
    case restored(BoardResponse)
    /// The undo ring was empty — a silent no-op.
    case nothingToUndo
    /// Undo was aborted because the board was edited by another process (the MCP server) since the
    /// mutation. Presentation surfaces this to the user, since the ⌘Z did nothing for a non-obvious
    /// reason.
    case abortedExternalEdit

    init(from outcome: UndoOutcome, mapper: BoardResponseMapper) {
        switch outcome {
        case .restored(let state):
            self = .restored(mapper.toBoardResponse(state))
        case .nothingToUndo:
            self = .nothingToUndo
        case .abortedExternalEdit:
            self = .abortedExternalEdit
        }
    }
}
