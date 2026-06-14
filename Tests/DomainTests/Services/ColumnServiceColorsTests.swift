import XCTest
@testable import KanvasCore

/// `ColumnService.settingColors` updates only the target column's header / body colours, leaving
/// every other column untouched.
final class ColumnServiceColorsTests: XCTestCase {

    private var service: ColumnService!

    override func setUp() {
        super.setUp()
        service = ColumnService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testSettingColors_updatesTargetColumnOnly() throws {
        let boardID = UUID()
        let target = Column(boardID: boardID, title: "A", sortIndex: 0)
        let other = Column(boardID: boardID, title: "B", sortIndex: 1, headerColorHex: "OLD")
        let state = BoardState(board: Board(id: boardID, title: "B"), columns: [target, other],
                               cards: [], stickies: [])

        let result = try service.settingColors(
            id: target.id,
            colors: ColumnColors(headerColorHex: "FF0000", bodyColorHex: "00FF00"),
            in: state
        )

        XCTAssertEqual(result.columns.first { $0.id == target.id }?.headerColorHex, "FF0000")
        XCTAssertEqual(result.columns.first { $0.id == target.id }?.bodyColorHex, "00FF00")
        XCTAssertEqual(result.columns.first { $0.id == other.id }?.headerColorHex, "OLD")
    }

    func testSettingColors_reflectsIndicatorColour() throws {
        let column = Column(boardID: UUID(), title: "A", sortIndex: 0)
        let state = BoardState(board: Board(title: "B"), columns: [column], cards: [], stickies: [])

        let result = try service.settingColors(
            id: column.id,
            colors: ColumnColors(indicatorColorHex: "FF9500"),
            in: state
        )

        XCTAssertEqual(result.columns.first?.indicatorColorHex, "FF9500")
    }

    func testSettingColors_nilClearsIndicatorColour() throws {
        let column = Column(boardID: UUID(), title: "A", sortIndex: 0, indicatorColorHex: "FF9500")
        let state = BoardState(board: Board(title: "B"), columns: [column], cards: [], stickies: [])

        let result = try service.settingColors(id: column.id, colors: ColumnColors(), in: state)

        XCTAssertNil(result.columns.first?.indicatorColorHex)
    }

    func testSettingColors_nilClearsColour() throws {
        let column = Column(boardID: UUID(), title: "A", sortIndex: 0, headerColorHex: "FF0000")
        let state = BoardState(board: Board(title: "B"), columns: [column], cards: [], stickies: [])

        let result = try service.settingColors(id: column.id, colors: ColumnColors(), in: state)

        XCTAssertNil(result.columns.first?.headerColorHex)
    }

    func testSettingColors_unknownID_throwsNotFound() {
        let column = Column(boardID: UUID(), title: "A", sortIndex: 0)
        let state = BoardState(board: Board(title: "B"), columns: [column], cards: [], stickies: [])
        let missingID = UUID()

        XCTAssertThrowsError(
            try service.settingColors(id: missingID, colors: ColumnColors(headerColorHex: "FF0000"), in: state)
        ) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Column", id: missingID))
        }
    }
}
