import XCTest
@testable import KanvasCore

/// `StickyService.togglingLabel` flips a label's membership on a sticky: it appends the id when
/// absent and removes it when already present.
final class StickyServiceLabelTests: XCTestCase {

    private var service: StickyService!

    override func setUp() {
        super.setUp()
        service = StickyService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func state(with sticky: Sticky) -> BoardState {
        let board = Board(title: "Board")
        return BoardState(board: board, columns: [], cards: [], stickies: [sticky], labels: [])
    }

    func testTogglingLabel_whenAbsent_assignsIt() throws {
        let labelID = UUID()
        let sticky = Sticky(cardID: UUID(), content: "a", position: .zero, sortIndex: 0)

        let result = try service.togglingLabel(stickyID: sticky.id, labelID: labelID, in: state(with: sticky))

        XCTAssertEqual(result.stickies.first?.labelIDs, [labelID])
    }

    func testTogglingLabel_whenPresent_removesIt() throws {
        let labelID = UUID()
        let sticky = Sticky(cardID: UUID(), content: "a", position: .zero, sortIndex: 0, labelIDs: [labelID])

        let result = try service.togglingLabel(stickyID: sticky.id, labelID: labelID, in: state(with: sticky))

        XCTAssertEqual(result.stickies.first?.labelIDs, [])
    }

    func testTogglingLabel_unknownSticky_throwsNotFound() {
        let missingID = UUID()
        let sticky = Sticky(cardID: UUID(), content: "a", position: .zero, sortIndex: 0)

        XCTAssertThrowsError(
            try service.togglingLabel(stickyID: missingID, labelID: UUID(), in: state(with: sticky))
        ) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Sticky", id: missingID))
        }
    }
}
