import Foundation

/// The board index: every board (id + title) in display order plus which one is active. The
/// catalog is the **authoritative source for a board's title** — a rename touches only the catalog,
/// never the per-board snapshot, and a freshly-loaded snapshot is reconciled to it on load.
///
/// This is the in-memory shape the `BoardRepository` reloads under its cross-process lock and the
/// value a board-catalog decision (which board becomes active after a delete, how a snapshot's title
/// is reconciled) is computed over. The *decisions* live in Domain (`BoardManagementService` /
/// `reconcilingTitle` below); the Repository only supplies the freshly-read catalog and persists the
/// computed result.
struct BoardCatalog: Sendable, Equatable {
    var boards: [Board]
    var activeBoardID: UUID?

    init(boards: [Board] = [], activeBoardID: UUID? = nil) {
        self.boards = boards
        self.activeBoardID = activeBoardID
    }

    /// Reconciles a freshly-loaded board snapshot's title to the catalog — the authoritative source.
    /// A catalog-only rename never rewrites the snapshot file, so the snapshot's own `board.title` is
    /// only a stale seed; on load it is overwritten with the catalogued title. Returns the state
    /// unchanged when the board is not catalogued (a legacy / migration seed that *establishes* the
    /// catalog entry). "Which copy of the title is authoritative" is a domain rule, so it lives here
    /// rather than in the Repository's load plumbing.
    func reconcilingTitle(of state: BoardState) -> BoardState {
        guard let ref = boards.first(where: { $0.id == state.board.id }) else { return state }
        var next = state
        next.board.title = ref.title
        return next
    }
}
