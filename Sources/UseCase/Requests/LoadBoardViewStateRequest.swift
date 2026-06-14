import Foundation

/// Request for the combined board-view-state read (ticket 8DCB811D). `openCardID` is the card whose
/// canvas the caller currently has open (or `nil` when none) — supplied so the use case can map that
/// card's refreshed detail from the **same** decoded state it loads the board from, sparing the
/// separate card-detail disk read. Carries no invariant, so it stays a bare `UseCaseRequest`.
///
/// `searchQuery` is the active card-filter text (or `nil`/blank when no filter is in effect). When
/// supplied, the use case applies the matcher over the **same** decoded state, returning the matched
/// ids in the response — so a live refresh with an active filter pays one store read, not two (the
/// former `refreshSearchIfActive` → `SearchCards` round-trip was a second flock + decode; PR #123 r2-1).
struct LoadBoardViewStateRequest: UseCaseRequest {
    let openCardID: UUID?
    let searchQuery: String?
}
