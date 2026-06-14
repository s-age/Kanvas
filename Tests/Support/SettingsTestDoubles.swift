import Synchronization
import XCTest
@testable import KanvasCore

// Test doubles shared by the SettingsViewModel test cases.

@MainActor
final class FakeBoardSettingsHost: BoardSettingsHost {
    var boards: [BoardSummary] = []
    var activeBoardID: UUID?
    private(set) var appliedBoards: [BoardResponse] = []

    func applyBoard(_ response: BoardResponse) {
        appliedBoards.append(response)
    }
}

final class MockEditBoardSettingsUseCase: AsyncUseCase, @unchecked Sendable {
    private let state = Mutex<(request: EditBoardSettingsRequest?, callCount: Int)>((nil, 0))

    var lastRequest: EditBoardSettingsRequest? { state.withLock { $0.request } }
    var executeCallCount: Int { state.withLock { $0.callCount } }

    func execute(_ request: EditBoardSettingsRequest) async throws -> BoardResponse {
        state.withLock { $0 = (request, $0.callCount + 1) }
        return SettingsTestFixtures.board(
            id: request.boardID,
            settings: BoardSettingsResponse(
                global: request.global, board: request.board,
                canvas: request.canvas, markdown: request.markdown
            )
        )
    }
}

final class MockLoadBoardByIDUseCase: AsyncUseCase, @unchecked Sendable {
    var response: BoardResponse?

    func execute(_ request: LoadBoardByIDRequest) async throws -> BoardResponse {
        response ?? SettingsTestFixtures.board(id: request.boardID, settings: SettingsTestFixtures.defaultSettings)
    }
}

final class MockLoadBoardTemplateUseCase: LoadBoardTemplateUseCase, @unchecked Sendable {
    var response: BoardTemplateResponse?

    func execute() async throws -> BoardTemplateResponse {
        response ?? BoardTemplateResponse(settings: SettingsTestFixtures.defaultSettings, columns: [])
    }
}

final class MockEditBoardTemplateUseCase: AsyncUseCase, @unchecked Sendable {
    private let state = Mutex<EditBoardTemplateRequest?>(nil)

    var lastRequest: EditBoardTemplateRequest? { state.withLock { $0 } }

    func execute(_ request: EditBoardTemplateRequest) async throws -> BoardTemplateResponse {
        state.withLock { $0 = request }
        return BoardTemplateResponse(
            settings: BoardSettingsResponse(
                global: request.global, board: request.board,
                canvas: request.canvas, markdown: request.markdown
            ),
            columns: request.columns
        )
    }
}

enum SettingsTestFixtures {
    static let defaultSettings = BoardSettingsResponse(
        global: GlobalSettingsResponse(backgroundColorHex: nil, textColorHex: nil, colorPalette: []),
        board: BoardTabSettingsResponse(
            cardSortPolicy: .manual, autoCompleteOnMove: true,
            cardBackgroundColorHex: nil, cardTextColorHex: nil, cardBorderColorHex: nil,
            textColorHex: nil, newCardPosition: .bottom
        ),
        canvas: CanvasSettingsResponse(
            stickyPresets: [], defaultFontSize: 13,
            defaultTextColorHex: StickyAppearance.defaultTextColorHex,
            freeStickyColorHex: nil, taskStickyColorHex: nil, initialZoomScale: 1, gridSnapInterval: 0
        ),
        markdown: MarkdownSettingsResponse(
            baseFontSize: 14, headingSizes: MarkdownAppearance.defaultHeadingSizes,
            codeColorHex: nil, quoteColorHex: nil, useMonospacedFont: false,
            codeBlockBackgroundColorHex: nil, quoteBorderColorHex: nil,
            quoteBorderWidth: MarkdownAppearance.defaultQuoteBorderWidth, linkColorHex: nil,
            editorBackgroundColorHex: nil, listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        )
    )

    static func board(
        id: UUID,
        settings: BoardSettingsResponse,
        columns: [ColumnResponse] = []
    ) -> BoardResponse {
        BoardResponse(
            board: BoardSummary(id: id, title: "Test"),
            columns: columns,
            labels: [],
            settings: settings
        )
    }
}
