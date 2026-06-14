import XCTest
@testable import KanvasCore

/// `BoardState.from(template:)` materialises a fresh board from the Default template: settings are
/// copied, and each `TemplateColumn` becomes a `Column` with a new board id / column id while
/// carrying over title / order / completion / colours.
final class BoardTemplateTests: XCTestCase {

    func testFromTemplate_copiesSettings() {
        var settings = BoardSettings.default
        settings.global.backgroundColorHex = "101010"
        let template = BoardTemplate(settings: settings, columns: BoardTemplate.default.columns)

        let state = BoardState.from(template: template, title: "New")

        XCTAssertEqual(state.settings.global.backgroundColorHex, "101010")
    }

    func testFromTemplate_materialisesColumnsWithBoardIDAndColours() {
        let template = BoardTemplate(
            settings: .default,
            columns: [
                TemplateColumn(title: "Backlog", sortIndex: 0, headerColorHex: "AA0000"),
                TemplateColumn(title: "Done", sortIndex: 1, isCompletionColumn: true, bodyColorHex: "00BB00"),
            ]
        )

        let state = BoardState.from(template: template, title: "New")

        XCTAssertEqual(state.columns.map(\.title), ["Backlog", "Done"])
        XCTAssertTrue(state.columns.allSatisfy { $0.boardID == state.board.id })
        XCTAssertEqual(state.columns[0].headerColorHex, "AA0000")
        XCTAssertEqual(state.columns[1].bodyColorHex, "00BB00")
        XCTAssertTrue(state.columns[1].isCompletionColumn)
    }

    func testFromTemplate_carriesIndicatorColour() {
        let template = BoardTemplate(
            settings: .default,
            columns: [TemplateColumn(title: "A", sortIndex: 0, indicatorColorHex: "ABCDEF")]
        )

        let state = BoardState.from(template: template, title: "New")

        XCTAssertEqual(state.columns.first?.indicatorColorHex, "ABCDEF")
    }

    func testFromTemplate_unsetIndicatorStaysNil() {
        let template = BoardTemplate(
            settings: .default,
            columns: [TemplateColumn(title: "A", sortIndex: 0)]
        )

        let state = BoardState.from(template: template, title: "New")

        XCTAssertNil(state.columns.first?.indicatorColorHex)
    }

    func testFromTemplate_assignsFreshColumnIDs() {
        let templateColumnID = UUID()
        let template = BoardTemplate(
            settings: .default,
            columns: [TemplateColumn(id: templateColumnID, title: "A", sortIndex: 0)]
        )

        let state = BoardState.from(template: template, title: "New")

        XCTAssertNotEqual(state.columns.first?.id, templateColumnID)
    }

    func testFromTemplate_reindexesSortIndexToOrder() {
        let template = BoardTemplate(
            settings: .default,
            columns: [
                TemplateColumn(title: "Second", sortIndex: 9),
                TemplateColumn(title: "First", sortIndex: 2),
            ]
        )

        let state = BoardState.from(template: template, title: "New")

        XCTAssertEqual(state.columns.map(\.title), ["First", "Second"])
        XCTAssertEqual(state.columns.map(\.sortIndex), [0, 1])
    }

    func testDefaultTemplate_seedsToDoInProgressDone() {
        XCTAssertEqual(BoardTemplate.default.columns.map(\.title), ["To Do", "In Progress", "Done"])
        XCTAssertEqual(BoardTemplate.default.columns.last?.isCompletionColumn, true)
    }

    func testDefaultTemplate_seedsIndicatorColours() {
        // The three seeded columns carry explicit blue / orange / green hexes so a fresh board keeps
        // the historical status-dot look; an added column (no seed) renders the neutral default.
        XCTAssertEqual(BoardTemplate.default.columns.map(\.indicatorColorHex),
                       ["007AFF", "FF9500", "34C759"])
    }
}
