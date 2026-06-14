import Foundation

/// The result of an `undo()` — a three-way distinction that replaces the former ambiguous
/// `BoardState?` (where `nil` meant **both** "nothing to undo" *and* "aborted because a foreign
/// writer edited the board"). The two non-restoring cases are benign no-ops to the model, but the
/// caller must tell them apart: an empty ring is the user pressing ⌘Z with nothing left, while an
/// external-edit abort is the cross-process divergence guard (ticket 875C3208) refusing to clobber
/// an intervening MCP edit — the latter warrants user feedback, the former does not.
enum UndoOutcome: Sendable, Equatable {
    /// The pre-mutation snapshot was restored — the active board reverted to this state.
    case restored(BoardState)
    /// The undo ring was empty: there was nothing to revert. A silent no-op.
    case nothingToUndo
    /// Undo was aborted because the on-disk board diverged from the post-state this process
    /// recorded — a foreign writer (the MCP server) edited the board since that mutation. Restoring
    /// would silently destroy that edit, so undo refuses and drops the stale ring. The caller should
    /// surface this to the user (the ⌘Z did nothing for a non-obvious reason). See
    /// `BoardRepositoryProtocol.undo()`.
    case abortedExternalEdit
}
