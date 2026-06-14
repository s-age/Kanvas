import Synchronization
import XCTest
@testable import KanvasCore

/// `SettingsViewModel`'s scope-aware load/save for the Markdown tab: `load` populates state from the
/// selected board (via the load-by-id use case), `save` threads the edited Markdown state into the
/// settings update request, and `resetActiveTab` / `canResetActiveTab` honour the Markdown branch.
@MainActor
final class SettingsViewModelMarkdownTests: XCTestCase {

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

    func testLoad_board_populatesMarkdownState() async {
        loadByID.response = makeBoard(markdown: MarkdownSettingsResponse(
            baseFontSize: 20,
            headingSizes: [30, 28, 26, 24, 22, 20],
            codeColorHex: "112233",
            quoteColorHex: "445566",
            useMonospacedFont: true,
            codeBlockBackgroundColorHex: "161B22",
            quoteBorderColorHex: "3B434B",
            quoteBorderWidth: 4,
            linkColorHex: "4493F8",
            editorBackgroundColorHex: nil, listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        ))

        await sut.load()

        XCTAssertEqual(sut.markdownBaseFontSize, 20)
        XCTAssertEqual(sut.markdownHeadingSizes, [30, 28, 26, 24, 22, 20])
        XCTAssertEqual(sut.markdownCodeColorHex, "112233")
        XCTAssertEqual(sut.markdownQuoteColorHex, "445566")
        XCTAssertTrue(sut.markdownUseMonospacedFont)
        XCTAssertEqual(sut.markdownCodeBlockBackgroundColorHex, "161B22")
        XCTAssertEqual(sut.markdownQuoteBorderColorHex, "3B434B")
        XCTAssertEqual(sut.markdownQuoteBorderWidth, 4)
        XCTAssertEqual(sut.markdownLinkColorHex, "4493F8")
    }

    func testLoad_board_populatesPhase3MarkdownState() async {
        loadByID.response = makeBoard(markdown: MarkdownSettingsResponse(
            baseFontSize: 14,
            headingSizes: MarkdownAppearance.defaultHeadingSizes,
            codeColorHex: nil, quoteColorHex: nil, useMonospacedFont: false,
            codeBlockBackgroundColorHex: nil, quoteBorderColorHex: nil,
            quoteBorderWidth: MarkdownAppearance.defaultQuoteBorderWidth, linkColorHex: nil,
            editorBackgroundColorHex: "0D1117", listIndentExtra: 8, listItemSpacing: 4, lineSpacing: 5, syntaxColorOverrides: [:]
        ))

        await sut.load()

        XCTAssertEqual(sut.markdownEditorBackgroundColorHex, "0D1117")
        XCTAssertEqual(sut.markdownListIndentExtra, 8)
        XCTAssertEqual(sut.markdownListItemSpacing, 4)
        XCTAssertEqual(sut.markdownLineSpacing, 5)
    }

    // MARK: - save

    func testSave_board_propagatesMarkdownStateIntoRequest() async {
        loadByID.response = makeBoard(markdown: defaultMarkdown)
        await sut.load()
        sut.markdownBaseFontSize = 18
        sut.markdownHeadingSizes = [31, 29, 27, 25, 23, 21]
        sut.markdownCodeColorHex = "AABBCC"
        sut.markdownQuoteColorHex = "DDEEFF"
        sut.markdownUseMonospacedFont = true
        sut.markdownCodeBlockBackgroundColorHex = "161B22"
        sut.markdownQuoteBorderColorHex = "3B434B"
        sut.markdownQuoteBorderWidth = 5
        sut.markdownLinkColorHex = "4493F8"

        await sut.save()

        let sent = updateSettings.lastRequest?.markdown
        XCTAssertEqual(sent?.baseFontSize, 18)
        XCTAssertEqual(sent?.headingSizes, [31, 29, 27, 25, 23, 21])
        XCTAssertEqual(sent?.codeColorHex, "AABBCC")
        XCTAssertEqual(sent?.quoteColorHex, "DDEEFF")
        XCTAssertEqual(sent?.useMonospacedFont, true)
        XCTAssertEqual(sent?.codeBlockBackgroundColorHex, "161B22")
        XCTAssertEqual(sent?.quoteBorderColorHex, "3B434B")
        XCTAssertEqual(sent?.quoteBorderWidth, 5)
        XCTAssertEqual(sent?.linkColorHex, "4493F8")
    }

    func testSave_board_propagatesPhase3MarkdownStateIntoRequest() async {
        loadByID.response = makeBoard(markdown: defaultMarkdown)
        await sut.load()
        sut.markdownEditorBackgroundColorHex = "0D1117"
        sut.markdownListIndentExtra = 8
        sut.markdownListItemSpacing = 4
        sut.markdownLineSpacing = 6

        await sut.save()

        let sent = updateSettings.lastRequest?.markdown
        XCTAssertEqual(sent?.editorBackgroundColorHex, "0D1117")
        XCTAssertEqual(sent?.listIndentExtra, 8)
        XCTAssertEqual(sent?.listItemSpacing, 4)
        XCTAssertEqual(sent?.lineSpacing, 6)
    }

    func testSave_board_targetsSelectedBoardID() async {
        loadByID.response = makeBoard(markdown: defaultMarkdown)
        await sut.load()

        await sut.save()

        XCTAssertEqual(updateSettings.lastRequest?.boardID, boardID)
    }

    // MARK: - resetActiveTab

    func testResetActiveTab_markdown_resetsStateToDefaults() async {
        loadByID.response = makeBoard(markdown: MarkdownSettingsResponse(
            baseFontSize: 22, headingSizes: [40, 38, 36, 34, 32, 30],
            codeColorHex: "111111", quoteColorHex: "222222", useMonospacedFont: true,
            codeBlockBackgroundColorHex: "AAAAAA", quoteBorderColorHex: "BBBBBB",
            quoteBorderWidth: 7, linkColorHex: "CCCCCC",
            editorBackgroundColorHex: nil, listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        ))
        await sut.load()
        sut.selectedTab = .markdown

        await sut.resetActiveTab()

        XCTAssertEqual(sut.markdownBaseFontSize, MarkdownAppearance.defaultBaseFontSize)
        XCTAssertEqual(sut.markdownHeadingSizes, MarkdownAppearance.defaultHeadingSizes)
        XCTAssertNil(sut.markdownCodeColorHex)
        XCTAssertNil(sut.markdownQuoteColorHex)
        XCTAssertEqual(sut.markdownUseMonospacedFont, MarkdownAppearance.defaultUseMonospacedFont)
        XCTAssertNil(sut.markdownCodeBlockBackgroundColorHex)
        XCTAssertNil(sut.markdownQuoteBorderColorHex)
        XCTAssertEqual(sut.markdownQuoteBorderWidth, MarkdownAppearance.defaultQuoteBorderWidth)
        XCTAssertNil(sut.markdownLinkColorHex)
        XCTAssertNil(sut.markdownEditorBackgroundColorHex)
        XCTAssertEqual(sut.markdownListIndentExtra, 0)
        XCTAssertEqual(sut.markdownListItemSpacing, 0)
        XCTAssertEqual(sut.markdownLineSpacing, MarkdownAppearance.defaultLineSpacing)
    }

    // MARK: - canResetActiveTab

    func testCanResetActiveTab_markdown_falseWhenAllDefault() {
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

        XCTAssertFalse(sut.canResetActiveTab)
    }

    func testCanResetActiveTab_markdown_trueWhenColorSet() {
        sut.selectedTab = .markdown
        sut.markdownCodeColorHex = "FF0000"

        XCTAssertTrue(sut.canResetActiveTab)
    }

    func testCanResetActiveTab_markdown_trueWhenCodeBlockBackgroundSet() {
        sut.selectedTab = .markdown
        sut.markdownCodeBlockBackgroundColorHex = "161B22"

        XCTAssertTrue(sut.canResetActiveTab)
    }

    func testCanResetActiveTab_markdown_trueWhenQuoteBorderWidthNonDefault() {
        sut.selectedTab = .markdown
        sut.markdownQuoteBorderWidth = 6

        XCTAssertTrue(sut.canResetActiveTab)
    }

    func testCanResetActiveTab_markdown_trueWhenLinkColorSet() {
        sut.selectedTab = .markdown
        sut.markdownLinkColorHex = "4493F8"

        XCTAssertTrue(sut.canResetActiveTab)
    }

    func testCanResetActiveTab_markdown_trueWhenBackgroundColorSet() {
        sut.selectedTab = .markdown
        sut.markdownEditorBackgroundColorHex = "0D1117"

        XCTAssertTrue(sut.canResetActiveTab)
    }

    func testCanResetActiveTab_markdown_trueWhenLineSpacingNonDefault() {
        sut.selectedTab = .markdown
        sut.markdownLineSpacing = 6

        XCTAssertTrue(sut.canResetActiveTab)
    }

    func testCanResetActiveTab_markdown_trueWhenListIndentWidthNonZero() {
        sut.selectedTab = .markdown
        sut.markdownListIndentExtra = 4

        XCTAssertTrue(sut.canResetActiveTab)
    }

    // MARK: - Helpers

    /// Default markdown response with nil paragraph-styling fields and domain defaults elsewhere.
    private var defaultMarkdown: MarkdownSettingsResponse {
        MarkdownSettingsResponse(
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
    }

    private func makeBoard(markdown: MarkdownSettingsResponse) -> BoardResponse {
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
                markdown: markdown
            )
        )
    }
}
