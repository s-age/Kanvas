import XCTest
@testable import KanvasCore

/// `LabelService` owns the app-wide sticky-label registry. The load-bearing rule pinned here is
/// `deleting`: removing a label must also strip its id from every sticky's `labelIDs`, so no
/// sticky is left tagging a label that no longer exists.
final class LabelServiceTests: XCTestCase {

    private var service: LabelService!

    override func setUp() {
        super.setUp()
        service = LabelService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func emptyState() -> BoardState {
        let board = Board(title: "Board")
        return BoardState(board: board, columns: [], cards: [], stickies: [], labels: [])
    }

    func testAdding_appendsLabelToRegistry() {
        let result = service.adding(name: "Urgent", colorHex: "FF0000", in: emptyState())

        XCTAssertEqual(result.labels.map(\.name), ["Urgent"])
    }

    func testEditing_updatesNameAndColor() throws {
        var state = emptyState()
        let label = StickyLabel(name: "Old", colorHex: "000000")
        state.labels = [label]

        let result = try service.editing(id: label.id, name: "New", colorHex: "00FF00", in: state)

        XCTAssertEqual(result.labels.first, StickyLabel(id: label.id, name: "New", colorHex: "00FF00"))
    }

    func testDeleting_removesLabelFromRegistry() throws {
        var state = emptyState()
        let label = StickyLabel(name: "Gone", colorHex: "112233")
        state.labels = [label]

        let result = try service.deleting(id: label.id, from: state)

        XCTAssertTrue(result.labels.isEmpty)
    }

    func testDeleting_unknownID_throwsNotFound() {
        let missingID = UUID()

        XCTAssertThrowsError(try service.deleting(id: missingID, from: emptyState())) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Label", id: missingID))
        }
    }

    func testDeleting_stripsLabelIDFromAllStickies() throws {
        var state = emptyState()
        let label = StickyLabel(name: "Shared", colorHex: "112233")
        state.labels = [label]
        let card = Card(columnID: UUID(), title: "C", sortIndex: 0)
        state.stickies = [
            Sticky(cardID: card.id, content: "a", position: .zero, sortIndex: 0, labelIDs: [label.id]),
            Sticky(cardID: card.id, content: "b", position: .zero, sortIndex: 1, labelIDs: [label.id]),
        ]

        let result = try service.deleting(id: label.id, from: state)

        XCTAssertEqual(result.stickies.flatMap(\.labelIDs), [])
    }
}
