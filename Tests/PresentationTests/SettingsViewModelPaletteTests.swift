import XCTest
@testable import KanvasCore

/// `SettingsViewModel`'s Global colour-palette editing: add / delete / recolour / relabel / reorder
/// mark the form dirty, same-value write-backs do not, load/save thread the palette through the
/// settings request, and `resetActiveTab` / `canResetActiveTab` honour the palette.
@MainActor
final class SettingsViewModelPaletteTests: XCTestCase {

    private var host: FakeBoardSettingsHost!
    private var updateSettings: MockEditBoardSettingsUseCase!
    private var loadByID: MockLoadBoardByIDUseCase!
    private var sut: SettingsViewModel!
    private let boardID = UUID()

    override func setUp() {
        super.setUp()
        host = FakeBoardSettingsHost()
        host.activeBoardID = boardID
        host.boards = [BoardSummary(id: boardID, title: "Test")]
        updateSettings = MockEditBoardSettingsUseCase()
        loadByID = MockLoadBoardByIDUseCase()
        sut = SettingsViewModel(
            boardHost: host,
            editBoardSettings: updateSettings,
            loadBoardByID: loadByID,
            loadBoardTemplate: MockLoadBoardTemplateUseCase(),
            editBoardTemplate: MockEditBoardTemplateUseCase()
        )
        sut.selectedScope = .board(boardID)
    }

    override func tearDown() {
        sut = nil
        loadByID = nil
        updateSettings = nil
        host = nil
        super.tearDown()
    }

    // MARK: - add / delete

    func testAddPaletteColor_appendsAndMarksDirty() {
        let before = sut.colorPalette.count

        sut.addPaletteColor()

        XCTAssertEqual(sut.colorPalette.count, before + 1)
        XCTAssertTrue(sut.isDirty)
    }

    func testDeletePaletteColor_removesByID() {
        let target = sut.colorPalette[2].id

        sut.deletePaletteColor(target)

        XCTAssertFalse(sut.colorPalette.contains { $0.id == target })
    }

    // MARK: - reorder

    func testMovePaletteColor_reordersAndMarksDirty() {
        let firstID = sut.colorPalette[0].id

        sut.movePaletteColor(fromOffsets: IndexSet(integer: 0), toOffset: 2)

        XCTAssertEqual(sut.colorPalette[1].id, firstID)
        XCTAssertTrue(sut.isDirty)
    }

    // MARK: - recolour / relabel

    func testSetPaletteColor_sameValueDoesNotMarkDirty() {
        let color = sut.colorPalette[0]

        sut.setPaletteColor(color.colorHex, for: color.id)

        XCTAssertFalse(sut.isDirty)
    }

    func testSetPaletteLabel_truncatesToMaxLength() {
        let id = sut.colorPalette[0].id
        let long = String(repeating: "あ", count: SettingsViewModel.maxPaletteLabelLength + 10)

        sut.setPaletteLabel(long, for: id)

        XCTAssertEqual(sut.colorPalette[0].label.count, SettingsViewModel.maxPaletteLabelLength)
    }

    // MARK: - save

    func testSave_board_propagatesPaletteIntoRequest() async {
        loadByID.response = makeBoard(palette: [PaletteColorResponse(id: UUID(), colorHex: "112233", label: "One")])
        await sut.load()
        sut.addPaletteColor()

        await sut.save()

        let sent = updateSettings.lastRequest?.global.colorPalette
        XCTAssertEqual(sent?.count, 2)
        XCTAssertEqual(sent?.first?.colorHex, "112233")
    }

    // MARK: - reset

    func testResetActiveTab_global_resetsPaletteToSeed() async {
        loadByID.response = makeBoard(palette: [PaletteColorResponse(id: UUID(), colorHex: "112233", label: "One")])
        await sut.load()
        sut.selectedTab = .global

        await sut.resetActiveTab()

        XCTAssertTrue(sut.paletteIsDefault)
    }

    func testCanResetActiveTab_global_trueWhenPaletteEdited() {
        sut.selectedTab = .global
        sut.addPaletteColor()

        XCTAssertTrue(sut.canResetActiveTab)
    }

    // MARK: - Helpers

    private func makeBoard(palette: [PaletteColorResponse]) -> BoardResponse {
        BoardResponse(
            board: BoardSummary(id: boardID, title: "Test"),
            columns: [],
            labels: [],
            settings: BoardSettingsResponse(
                global: GlobalSettingsResponse(backgroundColorHex: nil, textColorHex: nil, colorPalette: palette),
                board: BoardTabSettingsResponse(
                    cardSortPolicy: .manual,
                    autoCompleteOnMove: true,
                    cardBackgroundColorHex: nil,
                    cardTextColorHex: nil,
                    cardBorderColorHex: nil,
                    textColorHex: nil,
                    newCardPosition: .bottom
                ),
                canvas: CanvasSettingsResponse(
                    stickyPresets: [],
                    defaultFontSize: 13,
                    defaultTextColorHex: StickyAppearance.defaultTextColorHex,
                    freeStickyColorHex: nil,
                    taskStickyColorHex: nil,
                    initialZoomScale: 1,
                    gridSnapInterval: 0
                ),
                markdown: MarkdownSettingsResponse(
                    baseFontSize: 14,
                    headingSizes: MarkdownAppearance.defaultHeadingSizes,
                    codeColorHex: nil,
                    quoteColorHex: nil,
                    useMonospacedFont: false,
                    codeBlockBackgroundColorHex: nil,
                    quoteBorderColorHex: nil,
                    quoteBorderWidth: MarkdownAppearance.defaultQuoteBorderWidth,
                    linkColorHex: nil,
                    editorBackgroundColorHex: nil, listIndentExtra: 0, listItemSpacing: 0,
                    lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
                )
            )
        )
    }
}
