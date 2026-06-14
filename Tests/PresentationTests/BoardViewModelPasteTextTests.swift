import XCTest
@testable import KanvasCore

/// `BoardViewModel.copyText` / `pasteText` over a stub duplicate use case (ticket 254829BE — ⌘C/⌘V
/// for free-text, mirroring the sticky paste buffer). Copy remembers the source id and clears any
/// copied sticky (the single buffer holds one kind); paste duplicates the source once and selects the
/// new copy. With nothing copied, paste is a no-op.
@MainActor
final class BoardViewModelPasteTextTests: XCTestCase {

    private let cardID = UUID()
    private let sourceTextID = UUID()
    private let newTextID = UUID()
    private let sourceStickyID = UUID()

    func testCopyText_remembersSourceAndClearsCopiedSticky() async {
        let sut = makeBoardViewModel(loadCardDetail: detailLoader())
        sut.selectedCardID = cardID
        sut.copiedItem = .sticky(UUID())

        sut.copyText(id: sourceTextID)

        XCTAssertEqual(sut.copiedItem, .text(sourceTextID))
    }

    func testCopySticky_remembersSourceAndClearsCopiedText() async {
        let sut = makeBoardViewModel(loadCardDetail: detailLoader())
        sut.selectedCardID = cardID
        sut.copiedItem = .text(UUID())

        sut.copySticky(id: sourceStickyID)

        XCTAssertEqual(sut.copiedItem, .sticky(sourceStickyID))
    }

    func testPasteText_callsDuplicateOnce() async {
        let duplicate = SpyDuplicateText(cardID: cardID, sourceTextID: sourceTextID, newTextID: newTextID)
        let sut = makeBoardViewModel(loadCardDetail: detailLoader(), duplicateText: duplicate)
        sut.selectedCardID = cardID
        await waitForDetail(sut)
        sut.copyText(id: sourceTextID)

        await sut.pasteText()

        XCTAssertEqual(duplicate.callCount, 1)
    }

    func testPasteText_selectsNewCopy() async {
        let duplicate = SpyDuplicateText(cardID: cardID, sourceTextID: sourceTextID, newTextID: newTextID)
        let sut = makeBoardViewModel(loadCardDetail: detailLoader(), duplicateText: duplicate)
        sut.selectedCardID = cardID
        await waitForDetail(sut)
        sut.copyText(id: sourceTextID)

        await sut.pasteText()

        XCTAssertEqual(sut.selectedItems, [CanvasSelection.text(newTextID)])
    }

    func testPasteText_nothingCopied_doesNotCallDuplicate() async {
        let duplicate = SpyDuplicateText(cardID: cardID, sourceTextID: sourceTextID, newTextID: newTextID)
        let sut = makeBoardViewModel(loadCardDetail: detailLoader(), duplicateText: duplicate)
        sut.selectedCardID = cardID
        await waitForDetail(sut)

        await sut.pasteText()

        XCTAssertEqual(duplicate.callCount, 0)
    }

    // MARK: - Helpers

    /// `selectedCardID`'s `didSet` kicks off an async detail refresh; yield until it lands so the
    /// source text is present for the paste lookup.
    private func waitForDetail(_ sut: BoardViewModel) async {
        for _ in 0..<20 where sut.selectedCardDetail == nil {
            await Task.yield()
        }
    }

    private func detailLoader() -> any LoadCardDetailUseCase {
        StubTextDetail(cardID: cardID, texts: [pasteTestText(id: sourceTextID)])
    }
}

// MARK: - Test doubles

private func pasteTestText(id: UUID) -> TextResponse {
    TextResponse(
        id: id, content: "hi", positionX: 10, positionY: 20, width: 200, height: 80,
        minWidth: TextSize.minWidth, minHeight: TextSize.minHeight,
        maxWidth: TextSize.maxWidth, maxHeight: TextSize.maxHeight,
        textColorHex: CanvasTextStyle.defaultColorHex, fontSize: CanvasTextStyle.defaultFontSize,
        minFontSize: CanvasTextStyle.minFontSize, maxFontSize: CanvasTextStyle.maxFontSize,
        sortIndex: 0
    )
}

/// Echoes a card detail carrying the source text plus a freshly-added copy, so `pasteText`'s diff
/// resolves the new copy's id.
private final class SpyDuplicateText: AsyncUseCase, @unchecked Sendable {
    private(set) var callCount = 0
    private let cardID: UUID
    private let sourceTextID: UUID
    private let newTextID: UUID
    init(cardID: UUID, sourceTextID: UUID, newTextID: UUID) {
        self.cardID = cardID
        self.sourceTextID = sourceTextID
        self.newTextID = newTextID
    }

    func execute(_ request: DuplicateTextRequest) async throws -> BoardMutationResponse {
        callCount += 1
        let detail = CardDetailResponse(
            id: cardID, title: "Card", markdownContent: "",
            status: .todo, columnTitle: "To Do",
            schedule: nil, labels: [], assignee: nil, prURL: nil, completedAt: nil,
            stickies: [], shapes: [], images: [],
            texts: [pasteTestText(id: sourceTextID),
                    pasteTestText(id: newTextID)],
            connectors: []
        )
        return BoardMutationResponse(
            board: BoardResponse(board: BoardSummary(id: UUID(), title: ""), columns: [], labels: [],
                                 settings: SettingsTestFixtures.defaultSettings),
            cardDetail: detail
        )
    }
}

private final class StubTextDetail: LoadCardDetailUseCase, @unchecked Sendable {
    private let cardID: UUID
    private let texts: [TextResponse]
    init(cardID: UUID, texts: [TextResponse]) {
        self.cardID = cardID
        self.texts = texts
    }
    func execute(cardID: UUID) async throws -> CardDetailResponse? {
        CardDetailResponse(
            id: cardID, title: "Card", markdownContent: "",
            status: .todo, columnTitle: "To Do",
            schedule: nil, labels: [], assignee: nil, prURL: nil, completedAt: nil,
            stickies: [], shapes: [], images: [], texts: texts, connectors: []
        )
    }
}
