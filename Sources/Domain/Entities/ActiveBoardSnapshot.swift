import Foundation

/// The active board's full `state` **plus** the board catalog (`boards` + `activeBoardID`), read from
/// one `BoardRepository.exclusive` section under a single `flock` (ticket 8DCB811D). Bundling them in
/// a named entity — like `listBoards()` returning the named `BoardCatalog` rather than an anonymous
/// tuple — lets a refresh derive the board, the open card's detail, and the picker list from one
/// decode while keeping every layer's signature self-describing.
struct ActiveBoardSnapshot: Sendable, Equatable {
    let state: BoardState
    let boards: [Board]
    let activeBoardID: UUID?
}
