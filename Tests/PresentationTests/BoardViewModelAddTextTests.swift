import XCTest
@testable import KanvasCore

/// `BoardViewModel.addText` over a stub use case: it must call the add use case once and, after the
/// new (empty) text appears, request inline editing on it (ticket 7C1D6316 決め事 3 — a dropped text
/// is immediately editable).
@MainActor
final class BoardViewModelAddTextTests: XCTestCase {

    private let cardID = UUID()
    private let newTextID = UUID()

    func testAddText_callsAddUseCaseOnce() async throws {
        let add = SpyAddText(cardID: cardID, newTextID: newTextID)
        let sut = makeBoardViewModel(loadCardDetail: stubDetailLoader(), addText: add)
        sut.selectedCardID = cardID

        await sut.addText(cardID: cardID, x: 10, y: 20)

        XCTAssertEqual(add.callCount, 1)
    }

    func testAddText_requestsInlineEditOnNewText() async throws {
        let add = SpyAddText(cardID: cardID, newTextID: newTextID)
        let sut = makeBoardViewModel(loadCardDetail: stubDetailLoader(), addText: add)
        sut.selectedCardID = cardID

        await sut.addText(cardID: cardID, x: 10, y: 20)

        XCTAssertEqual(sut.textAwaitingEdit, newTextID)
    }

    /// The detail loader returns no texts initially; the add use case's returned detail carries the
    /// new (empty) text, so the diff in `addText` resolves its id.
    private func stubDetailLoader() -> any LoadCardDetailUseCase {
        StubEmptyCardDetail(cardID: cardID)
    }
}

// MARK: - Test doubles

private final class SpyAddText: AsyncUseCase, @unchecked Sendable {
    private(set) var callCount = 0
    private let cardID: UUID
    private let newTextID: UUID
    init(cardID: UUID, newTextID: UUID) {
        self.cardID = cardID
        self.newTextID = newTextID
    }

    func execute(_ request: AddTextRequest) async throws -> BoardMutationResponse {
        callCount += 1
        let detail = CardDetailResponse(
            id: cardID, title: "Card", markdownContent: "",
            status: .todo, columnTitle: "To Do",
            schedule: nil, labels: [], assignee: nil, prURL: nil, completedAt: nil,
            stickies: [], shapes: [], images: [],
            texts: [TextResponse(
                id: newTextID, content: "", positionX: 10, positionY: 20, width: 200, height: 80,
                minWidth: TextSize.minWidth, minHeight: TextSize.minHeight,
                maxWidth: TextSize.maxWidth, maxHeight: TextSize.maxHeight,
                textColorHex: CanvasTextStyle.defaultColorHex, fontSize: CanvasTextStyle.defaultFontSize,
                minFontSize: CanvasTextStyle.minFontSize, maxFontSize: CanvasTextStyle.maxFontSize,
                sortIndex: 0
            )],
            connectors: []
        )
        return BoardMutationResponse(
            board: BoardResponse(board: BoardSummary(id: UUID(), title: ""), columns: [], labels: [],
                                 settings: SettingsTestFixtures.defaultSettings),
            cardDetail: detail
        )
    }
}

private final class StubEmptyCardDetail: LoadCardDetailUseCase, @unchecked Sendable {
    private let cardID: UUID
    init(cardID: UUID) { self.cardID = cardID }
    func execute(cardID: UUID) async throws -> CardDetailResponse? {
        CardDetailResponse(
            id: cardID, title: "Card", markdownContent: "",
            status: .todo, columnTitle: "To Do",
            schedule: nil, labels: [], assignee: nil, prURL: nil, completedAt: nil,
            stickies: [], shapes: [], images: [], texts: [], connectors: []
        )
    }
}
