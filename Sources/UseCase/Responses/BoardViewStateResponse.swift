import Foundation

/// The full state a board refresh publishes, assembled from **one** store read (ticket 8DCB811D):
/// the active `board`, the picker `boardList`, and — when an `openCardID` was supplied and still
/// resolves in the snapshot — that card's refreshed `cardDetail`.
///
/// Folds what `LoadActiveBoard` + `ListBoards` + `LoadCardDetail` previously fetched in three
/// separate flock + decode round-trips into a single response, so the external-change watcher path
/// (`BoardViewModel.load()`) reloads the store once, not three times. `cardDetail` mirrors
/// `BoardMutationResponse.cardDetail`: it is `nil` when no card was open or the open card no longer
/// exists (e.g. deleted by the other process), and the caller then falls back to a fresh load.
struct BoardViewStateResponse: Sendable, Equatable {
    let board: BoardResponse
    let boardList: BoardListResponse
    let cardDetail: CardDetailResponse?
    /// The active-board card ids matching the request's `searchQuery`, computed over the **same**
    /// decoded state as `board` so a filtered live refresh needs no second store read (PR #123 r2-1).
    /// `nil` when the request carried no filter (blank query) — the "show every card" sentinel the
    /// ViewModel maps straight onto `matchedCardIDs`.
    let matchedCardIDs: Set<UUID>?
    /// The trimmed filter text this `matchedCardIDs` was computed for (empty when no filter). Returned
    /// so the caller can drop a **stale** result: an async refresh may land after the user typed on,
    /// and `matchedCardIDs` for the old query must not overwrite the field's current filter (PR #123
    /// r2-1). The ViewModel adopts the ids only while this still equals the live search field.
    let matchedQuery: String
}
