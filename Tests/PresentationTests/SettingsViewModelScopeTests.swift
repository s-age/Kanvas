import XCTest
@testable import KanvasCore

/// `SettingsViewModel`'s scope behaviour: the sidebar lists "Default" + every board, the template
/// scope loads/saves the column blueprint with full structural editing, and a board scope routes
/// column-colour edits through the by-id save path without switching the active board.
@MainActor
final class SettingsViewModelScopeTests: XCTestCase {

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

    // MARK: - scopes

    func testScopes_listDefaultThenBoards() {
        XCTAssertEqual(sut.scopes, [.template, .board(boardID)])
    }

    func testScopeTitle_templateIsDefault() {
        XCTAssertEqual(sut.scopeTitle(.template), "Default")
        XCTAssertEqual(sut.scopeTitle(.board(boardID)), "Board A")
    }

    func testPrepareInitialScope_selectsActiveBoard() {
        sut.prepareInitialScope()
        XCTAssertEqual(sut.selectedScope, .board(boardID))
    }

    // MARK: - template scope

    func testLoadTemplate_populatesEditableColumns() async {
        loadTemplate.response = BoardTemplateResponse(
            settings: SettingsTestFixtures.defaultSettings,
            columns: [
                TemplateColumnResponse(id: UUID(), title: "To Do", sortIndex: 0,
                                       isCompletionColumn: false, headerColorHex: "AA", headerTextColorHex: nil,
                                       bodyColorHex: nil, headerBorderColorHex: nil, bodyBorderColorHex: nil),
            ]
        )
        sut.selectedScope = .template

        await sut.load()

        XCTAssertEqual(sut.editableColumns.map(\.title), ["To Do"])
        XCTAssertEqual(sut.editableColumns.first?.headerColorHex, "AA")
    }

    func testSaveTemplate_sendsEditedColumns() async {
        sut.selectedScope = .template
        await sut.load()
        sut.addColumn()

        await sut.save()

        XCTAssertEqual(updateTemplate.lastRequest?.columns.last?.title, "New Column")
    }

    func testAddColumn_marksDirty() async {
        sut.selectedScope = .template
        await sut.load()

        sut.addColumn()

        XCTAssertTrue(sut.isDirty)
    }

    func testSetColumnCompletion_on_isExclusive() async {
        loadTemplate.response = BoardTemplateResponse(
            settings: SettingsTestFixtures.defaultSettings,
            columns: [
                TemplateColumnResponse(id: UUID(), title: "A", sortIndex: 0, isCompletionColumn: true,
                                       headerColorHex: nil, headerTextColorHex: nil, bodyColorHex: nil,
                                       headerBorderColorHex: nil, bodyBorderColorHex: nil),
                TemplateColumnResponse(id: UUID(), title: "B", sortIndex: 1, isCompletionColumn: false,
                                       headerColorHex: nil, headerTextColorHex: nil, bodyColorHex: nil,
                                       headerBorderColorHex: nil, bodyBorderColorHex: nil),
            ]
        )
        sut.selectedScope = .template
        await sut.load()
        let bID = sut.editableColumns[1].id

        sut.setColumnCompletion(bID, isOn: true)

        XCTAssertEqual(sut.editableColumns.filter(\.isCompletionColumn).map(\.id), [bID])
    }

    func testSetColumnCompletion_off_clearsFlag() async {
        loadTemplate.response = BoardTemplateResponse(
            settings: SettingsTestFixtures.defaultSettings,
            columns: [
                TemplateColumnResponse(id: UUID(), title: "A", sortIndex: 0, isCompletionColumn: true,
                                       headerColorHex: nil, headerTextColorHex: nil, bodyColorHex: nil,
                                       headerBorderColorHex: nil, bodyBorderColorHex: nil),
            ]
        )
        sut.selectedScope = .template
        await sut.load()
        let aID = sut.editableColumns[0].id

        sut.setColumnCompletion(aID, isOn: false)

        XCTAssertTrue(sut.editableColumns.filter(\.isCompletionColumn).isEmpty)
    }

    // MARK: - reset clears column colours

    func testResetBoardTab_clearsColumnColours() async {
        let columnID = UUID()
        loadByID.response = SettingsTestFixtures.board(
            id: boardID,
            settings: SettingsTestFixtures.defaultSettings,
            columns: [ColumnResponse(id: columnID, title: "Col", sortIndex: 0, isCompletionColumn: false,
                                     headerColorHex: "FF0000", headerTextColorHex: nil, bodyColorHex: "00FF00",
                                     headerBorderColorHex: nil, bodyBorderColorHex: nil, indicatorColorHex: nil, cards: [])]
        )
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.selectedTab = .board

        await sut.resetActiveTab()

        XCTAssertNil(sut.editableColumns.first?.headerColorHex)
        XCTAssertNil(sut.editableColumns.first?.bodyColorHex)
        XCTAssertEqual(updateSettings.lastRequest?.columns.first?.headerColorHex, nil)
    }

    func testSaveBoard_includesBoardTextColor() async {
        loadByID.response = SettingsTestFixtures.board(id: boardID, settings: SettingsTestFixtures.defaultSettings)
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.boardTextColorHex = "123456"

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.board.textColorHex, "123456")
    }

    func testSaveBoard_includesCardColors() async {
        loadByID.response = SettingsTestFixtures.board(id: boardID, settings: SettingsTestFixtures.defaultSettings)
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.cardBackgroundColorHex = "111111"
        sut.cardTextColorHex = "EEEEEE"

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.board.cardBackgroundColorHex, "111111")
        XCTAssertEqual(updateSettings.lastRequest?.board.cardTextColorHex, "EEEEEE")
    }

    // MARK: - board scope

    func testSaveBoard_isSingleUseCaseCall() async {
        // Settings + column colours go through ONE use-case call (one mutateBoard ⇒ one undo entry,
        // one disk write) — not the former settings-then-colours split.
        loadByID.response = SettingsTestFixtures.board(id: boardID, settings: SettingsTestFixtures.defaultSettings)
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.setHeaderColor("FF0000", for: UUID())  // a change, so the save is non-trivial

        await sut.save()

        XCTAssertEqual(updateSettings.executeCallCount, 1)
    }

    func testSaveBoard_sendsColumnColorsForSelectedBoard() async {
        let columnID = UUID()
        loadByID.response = SettingsTestFixtures.board(
            id: boardID,
            settings: SettingsTestFixtures.defaultSettings,
            columns: [ColumnResponse(id: columnID, title: "Col", sortIndex: 0, isCompletionColumn: false,
                                     headerColorHex: nil, headerTextColorHex: nil, bodyColorHex: nil,
                                     headerBorderColorHex: nil, bodyBorderColorHex: nil, indicatorColorHex: nil, cards: [])]
        )
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.setHeaderColor("FF0000", for: columnID)

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.boardID, boardID)
        XCTAssertEqual(updateSettings.lastRequest?.columns.first?.headerColorHex, "FF0000")
    }

    func testSaveBoard_sendsColumnHeaderTextColor() async {
        let columnID = UUID()
        loadByID.response = SettingsTestFixtures.board(
            id: boardID,
            settings: SettingsTestFixtures.defaultSettings,
            columns: [ColumnResponse(id: columnID, title: "Col", sortIndex: 0, isCompletionColumn: false,
                                     headerColorHex: nil, headerTextColorHex: nil,
                                     bodyColorHex: nil, headerBorderColorHex: nil, bodyBorderColorHex: nil, indicatorColorHex: nil, cards: [])]
        )
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.setHeaderTextColor("FEDCBA", for: columnID)

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.columns.first?.headerTextColorHex, "FEDCBA")
    }

    func testSaveBoard_sendsCompletionFlag() async {
        let columnID = UUID()
        loadByID.response = SettingsTestFixtures.board(
            id: boardID,
            settings: SettingsTestFixtures.defaultSettings,
            columns: [ColumnResponse(id: columnID, title: "Col", sortIndex: 0, isCompletionColumn: false,
                                     headerColorHex: nil, headerTextColorHex: nil, bodyColorHex: nil,
                                     headerBorderColorHex: nil, bodyBorderColorHex: nil, indicatorColorHex: nil, cards: [])]
        )
        sut.selectedScope = .board(boardID)
        await sut.load()
        sut.setColumnCompletion(columnID, isOn: true)

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.columns.first?.isCompletionColumn, true)
    }

    func testSaveActiveBoard_appliesResultToHost() async {
        loadByID.response = SettingsTestFixtures.board(id: boardID, settings: SettingsTestFixtures.defaultSettings)
        sut.selectedScope = .board(boardID)
        await sut.load()

        await sut.save()

        XCTAssertEqual(host.appliedBoards.count, 1)
    }

    func testSaveNonActiveBoard_doesNotApplyToHost() async {
        let otherID = UUID()
        host.boards = [BoardSummary(id: boardID, title: "A"), BoardSummary(id: otherID, title: "B")]
        loadByID.response = SettingsTestFixtures.board(id: otherID, settings: SettingsTestFixtures.defaultSettings)
        sut.selectedScope = .board(otherID)
        await sut.load()

        await sut.save()

        XCTAssertTrue(host.appliedBoards.isEmpty)
    }
}
