import XCTest
@testable import KanvasCore

/// The catalog-authoritative title rule, expressed as the pure `BoardCatalog.reconcilingTitle(of:)`
/// transform the Repository applies on load (it used to be open-coded inside `loadState`). The
/// catalog wins over a stale snapshot title; a board absent from the catalog is left untouched.
final class BoardCatalogTests: XCTestCase {

    private func state(boardID: UUID, title: String) -> BoardState {
        BoardState(board: Board(id: boardID, title: title), columns: [], cards: [], stickies: [])
    }

    func testReconcilingTitle_cataloguedBoard_overwritesSnapshotTitleWithCatalogTitle() {
        let boardID = UUID()
        let catalog = BoardCatalog(boards: [Board(id: boardID, title: "Renamed")], activeBoardID: boardID)
        let snapshot = state(boardID: boardID, title: "Stale")

        let reconciled = catalog.reconcilingTitle(of: snapshot)

        XCTAssertEqual(reconciled.board.title, "Renamed")
    }

    func testReconcilingTitle_uncataloguedBoard_leavesTitleUntouched() {
        // A legacy / migration seed that is not yet catalogued keeps its own title (it *establishes*
        // the catalog entry rather than being overwritten by it).
        let snapshot = state(boardID: UUID(), title: "Seed")
        let catalog = BoardCatalog(boards: [Board(id: UUID(), title: "Other")], activeBoardID: nil)

        let reconciled = catalog.reconcilingTitle(of: snapshot)

        XCTAssertEqual(reconciled.board.title, "Seed")
    }
}
