import XCTest
@testable import KanvasCore

/// `SettingsViewModel`'s scope-aware handling of the Markdown tab's per-token
/// `markdownSyntaxColorOverrides` map: `load` populates it from the selected board, `save` threads
/// it into the settings update request, `resetActiveTab` clears it to `[:]`, `canResetActiveTab`
/// flips true once any override is set, and the set/clear contract the syntax-override binding
/// relies on (a present hex = override, removing the key = inherit the built-in palette).
@MainActor
final class SettingsViewModelSyntaxOverrideTests: XCTestCase {

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

    // MARK: - load

    func testLoad_board_populatesSyntaxColorOverrides() async {
        loadByID.response = makeBoard(syntaxColorOverrides: ["keyword": "FF7B72", "string": "A5D6FF"])

        await sut.load()

        XCTAssertEqual(sut.markdownSyntaxColorOverrides, ["keyword": "FF7B72", "string": "A5D6FF"])
    }

    // MARK: - save

    func testSave_board_propagatesSyntaxColorOverridesIntoRequest() async {
        loadByID.response = makeBoard(syntaxColorOverrides: [:])
        await sut.load()
        sut.markdownSyntaxColorOverrides = ["comment": "8B949E"]

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.markdown.syntaxColorOverrides, ["comment": "8B949E"])
    }

    // MARK: - set / clear (the syntax-override binding contract)

    func testSetSyntaxOverride_storesHexUnderTokenKey() {
        sut.markdownSyntaxColorOverrides["keyword"] = "FF7B72"

        XCTAssertEqual(sut.markdownSyntaxColorOverrides["keyword"], "FF7B72")
    }

    func testClearSyntaxOverride_removesKeyToInheritBuiltInPalette() {
        sut.markdownSyntaxColorOverrides = ["keyword": "FF7B72"]

        sut.markdownSyntaxColorOverrides.removeValue(forKey: "keyword")

        XCTAssertNil(sut.markdownSyntaxColorOverrides["keyword"])
    }

    // MARK: - resetActiveTab

    func testResetActiveTab_markdown_clearsSyntaxColorOverrides() async {
        loadByID.response = makeBoard(syntaxColorOverrides: ["keyword": "FF7B72", "number": "79C0FF"])
        await sut.load()
        sut.selectedTab = .markdown

        await sut.resetActiveTab()

        XCTAssertEqual(sut.markdownSyntaxColorOverrides, [:])
    }

    // MARK: - canResetActiveTab

    func testCanResetActiveTab_markdown_trueWhenSyntaxOverrideSet() {
        sut.selectedTab = .markdown
        sut.markdownSyntaxColorOverrides = ["keyword": "FF7B72"]

        XCTAssertTrue(sut.canResetActiveTab)
    }

    func testCanResetActiveTab_markdown_falseWhenSyntaxOverridesEmpty() {
        sut.selectedTab = .markdown
        sut.markdownBaseFontSize = MarkdownAppearance.defaultBaseFontSize
        sut.markdownHeadingSizes = MarkdownAppearance.defaultHeadingSizes
        sut.markdownCodeColorHex = nil
        sut.markdownQuoteColorHex = nil
        sut.markdownUseMonospacedFont = MarkdownAppearance.defaultUseMonospacedFont
        sut.markdownCodeBlockBackgroundColorHex = nil
        sut.markdownQuoteBorderColorHex = nil
        sut.markdownQuoteBorderWidth = MarkdownAppearance.defaultQuoteBorderWidth
        sut.markdownLinkColorHex = nil
        sut.markdownEditorBackgroundColorHex = nil
        sut.markdownListIndentExtra = 0
        sut.markdownListItemSpacing = 0
        sut.markdownLineSpacing = MarkdownAppearance.defaultLineSpacing
        sut.markdownSyntaxColorOverrides = [:]

        XCTAssertFalse(sut.canResetActiveTab)
    }

    // MARK: - Helpers

    private func makeBoard(syntaxColorOverrides: [String: String]) -> BoardResponse {
        BoardResponse(
            board: BoardSummary(id: boardID, title: "Test"),
            columns: [],
            labels: [],
            settings: BoardSettingsResponse(
                global: GlobalSettingsResponse(backgroundColorHex: nil, textColorHex: nil, colorPalette: []),
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
                    editorBackgroundColorHex: nil,
                    listIndentExtra: 0,
                    listItemSpacing: 0,
                    lineSpacing: MarkdownAppearance.defaultLineSpacing,
                    syntaxColorOverrides: syntaxColorOverrides
                )
            )
        )
    }
}
