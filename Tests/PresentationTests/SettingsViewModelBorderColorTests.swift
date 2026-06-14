import XCTest
@testable import KanvasCore

/// `SettingsViewModel`'s border-colour wiring: a board-scope save carries the board-wide card
/// border colour and per-column header/body border colours through to the update request, and
/// editing a border colour marks the view model dirty (so the footer Save/Reset enable).
@MainActor
final class SettingsViewModelBorderColorTests: XCTestCase {

    private var host: FakeBoardSettingsHost!
    private var updateSettings: MockEditBoardSettingsUseCase!
    private var loadByID: MockLoadBoardByIDUseCase!
    private var loadTemplate: MockLoadBoardTemplateUseCase!
    private var updateTemplate: MockEditBoardTemplateUseCase!
    private var sut: SettingsViewModel!
    private let boardID = UUID()

    override func setUp() {
        super.setUp()
        host = FakeBoardSettingsHost()
        host.boards = [BoardSummary(id: boardID, title: "Board A")]
        host.activeBoardID = boardID
        updateSettings = MockEditBoardSettingsUseCase()
        loadByID = MockLoadBoardByIDUseCase()
        loadTemplate = MockLoadBoardTemplateUseCase()
        updateTemplate = MockEditBoardTemplateUseCase()
        sut = SettingsViewModel(
            boardHost: host,
            editBoardSettings: updateSettings,
            loadBoardByID: loadByID,
            loadBoardTemplate: loadTemplate,
            editBoardTemplate: updateTemplate
        )
    }

    override func tearDown() {
        sut = nil
        updateTemplate = nil; loadTemplate = nil; loadByID = nil; updateSettings = nil
        host = nil
        super.tearDown()
    }

    /// A column carrying no colours — the starting fixture for the border tests.
    private func plainColumn(_ id: UUID) -> ColumnResponse {
        ColumnResponse(id: id, title: "Col", sortIndex: 0, isCompletionColumn: false,
                       headerColorHex: nil, headerTextColorHex: nil, bodyColorHex: nil,
                       headerBorderColorHex: nil, bodyBorderColorHex: nil, indicatorColorHex: nil,
                       cards: [])
    }

    func testSaveBoard_includesCardBorderColor() async {
        loadByID.response = SettingsTestFixtures.board(id: boardID, settings: SettingsTestFixtures.defaultSettings)
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.cardBorderColorHex = "222222"

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.board.cardBorderColorHex, "222222")
    }

    func testSaveBoard_sendsColumnHeaderBorderColor() async {
        let columnID = UUID()
        loadByID.response = SettingsTestFixtures.board(
            id: boardID, settings: SettingsTestFixtures.defaultSettings, columns: [plainColumn(columnID)])
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.setHeaderBorderColor("AA0000", for: columnID)

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.columns.first?.headerBorderColorHex, "AA0000")
    }

    func testSaveBoard_sendsColumnBodyBorderColor() async {
        let columnID = UUID()
        loadByID.response = SettingsTestFixtures.board(
            id: boardID, settings: SettingsTestFixtures.defaultSettings, columns: [plainColumn(columnID)])
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.setBodyBorderColor("00BB00", for: columnID)

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.columns.first?.bodyBorderColorHex, "00BB00")
    }

    func testSaveBoard_sendsColumnIndicatorColor() async {
        let columnID = UUID()
        loadByID.response = SettingsTestFixtures.board(
            id: boardID, settings: SettingsTestFixtures.defaultSettings, columns: [plainColumn(columnID)])
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.setIndicatorColor("123456", for: columnID)

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.columns.first?.indicatorColorHex, "123456")
    }

    func testSetIndicatorColor_marksDirty() async {
        let columnID = UUID()
        loadByID.response = SettingsTestFixtures.board(
            id: boardID, settings: SettingsTestFixtures.defaultSettings, columns: [plainColumn(columnID)])
        sut.selectedScope = .board(boardID)
        await sut.load()
        XCTAssertFalse(sut.isDirty)

        sut.setIndicatorColor("123456", for: columnID)

        XCTAssertTrue(sut.isDirty)
    }

    func testSetHeaderBorderColor_marksDirty() async {
        let columnID = UUID()
        loadByID.response = SettingsTestFixtures.board(
            id: boardID, settings: SettingsTestFixtures.defaultSettings, columns: [plainColumn(columnID)])
        sut.selectedScope = .board(boardID)
        await sut.load()
        XCTAssertFalse(sut.isDirty)

        sut.setHeaderBorderColor("AA0000", for: columnID)

        XCTAssertTrue(sut.isDirty)
    }
}
