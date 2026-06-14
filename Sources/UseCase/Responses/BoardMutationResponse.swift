import Foundation

/// The result of a canvas/card mutation: the refreshed `board` plus, when resolvable, the
/// post-mutation detail of the card whose canvas the mutation touched.
///
/// `cardDetail` lets the caller (the `BoardViewModel`, the MCP gateway) refresh the open canvas
/// **without a second disk read** — every mutation already re-loaded and transformed the whole
/// `BoardState`, so the affected card's detail is free to map from the returned state instead of
/// re-reading it through `LoadCardDetailUseCase → loadActiveBoard` (ticket 1DCBF9C9).
///
/// It is `nil` when the mutation has no single owning card to refresh (a board/column/label-registry
/// op) or the card no longer exists (it was the deleted card, or the caller supplied no card id) —
/// the caller then falls back to a fresh load. `board` keeps its own `Equatable` identity separate
/// from `cardDetail`, so a canvas edit that leaves the Kanban board unchanged still compares equal on
/// `board` and the self-echo suppression in `applyBoardMutation` holds (ticket 5BC2FF20).
struct BoardMutationResponse: Sendable, Equatable {
    let board: BoardResponse
    let cardDetail: CardDetailResponse?
}
