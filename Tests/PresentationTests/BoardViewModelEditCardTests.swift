import Synchronization
import XCTest
@testable import KanvasCore

/// `BoardViewModel.editCard` reports whether the write was persisted. The Markdown autosave
/// (`MarkdownEditorView.save()`) relies on this Bool to clear its dirty baseline **only** on
/// success — a failed save must stay dirty so the next flush/autosave retries instead of
/// silently dropping the edit. This pins that contract (ticket 7CF1F5F1).
@MainActor
final class BoardViewModelEditCardTests: XCTestCase {

    private var mockEdit: ConfigurableEditCardUseCase!
    private var sut: BoardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockEdit = ConfigurableEditCardUseCase()
        sut = makeBoardViewModel(editCard: mockEdit)
    }

    override func tearDown() async throws {
        sut = nil
        mockEdit = nil
        try await super.tearDown()
    }

    // MARK: - editCard

    func testEditCard_success_returnsTrue() async {
        let saved = await sut.editCard(EditCardRequest(cardID: UUID(), markdownContent: "notes"))

        XCTAssertTrue(saved)
    }

    func testEditCard_failure_returnsFalse() async {
        mockEdit.error = OperationError.saveFailed

        let saved = await sut.editCard(EditCardRequest(cardID: UUID(), markdownContent: "notes"))

        XCTAssertFalse(saved)
    }

    func testEditCard_failure_surfacesViaError() async {
        mockEdit.error = OperationError.saveFailed

        _ = await sut.editCard(EditCardRequest(cardID: UUID(), markdownContent: "notes"))

        XCTAssertEqual(sut.error as? OperationError, .saveFailed)
    }
}

// MARK: - Configurable edit stub

private final class ConfigurableEditCardUseCase: AsyncUseCase, @unchecked Sendable {
    private let storedError = Mutex<(any Error)?>(nil)

    var error: (any Error)? {
        get { storedError.withLock { $0 } }
        set { storedError.withLock { $0 = newValue } }
    }

    func execute(_ request: EditCardRequest) async throws -> BoardMutationResponse {
        if let error = storedError.withLock({ $0 }) { throw error }
        return stubBoardMutation()
    }
}
