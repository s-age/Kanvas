import Synchronization
import XCTest
@testable import KanvasCore

/// `BoardViewModel.deleteSticky` (the canvas delete path, shared via `applyCanvasDelete`):
/// - a `notFound` is a **silent no-op** — the element is already gone (a second ⌫ on a stale
///   selection, or another process deleted it), so no alert is raised and the stale selection is
///   cleared. This pins the regression introduced when delete gerunds started throwing `notFound`
///   instead of silently no-op'ing.
/// - a successful delete clears the selection when it targeted the removed item.
/// - any *other* error still surfaces via `error`.
///
/// Also covers `BoardViewModel.undo` (a sibling action in `+StickyActions`): an
/// `.abortedExternalEdit` outcome surfaces the one-shot `notice` (ticket D1436DAB), while
/// `.nothingToUndo` stays silent — the two cases the former ambiguous `nil` could not distinguish.
@MainActor
final class BoardViewModelDeleteTests: XCTestCase {

    private var mockDelete: ConfigurableDeleteStickyUseCase!
    private var sut: BoardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockDelete = ConfigurableDeleteStickyUseCase()
        sut = makeBoardViewModel(deleteSticky: mockDelete)
    }

    override func tearDown() async throws {
        sut = nil
        mockDelete = nil
        try await super.tearDown()
    }

    // MARK: - deleteSticky

    func testDeleteSticky_notFound_doesNotSurfaceError() async {
        let id = UUID()
        mockDelete.error = OperationError.notFound(entityKind: "Sticky", id: id)

        await sut.deleteSticky(id: id)

        XCTAssertNil(sut.error)
    }

    func testDeleteSticky_notFound_clearsStaleSelection() async {
        let id = UUID()
        sut.select(stickyID: id)
        mockDelete.error = OperationError.notFound(entityKind: "Sticky", id: id)

        await sut.deleteSticky(id: id)

        XCTAssertNil(sut.selection)
    }

    func testDeleteSticky_success_clearsSelectionOfDeletedItem() async {
        let id = UUID()
        sut.select(stickyID: id)

        await sut.deleteSticky(id: id)

        XCTAssertNil(sut.selection)
    }

    func testDeleteSticky_genuineError_surfacesViaError() async {
        mockDelete.error = OperationError.saveFailed

        await sut.deleteSticky(id: UUID())

        XCTAssertEqual(sut.error as? OperationError, .saveFailed)
    }

    // MARK: - undo

    func testUndo_abortedExternalEdit_setsNotice() async {
        let vm = makeBoardViewModel(deleteSticky: ConfigurableDeleteStickyUseCase(),
                                    undo: ConfigurableUndoUseCase(.abortedExternalEdit))

        await vm.undo()

        XCTAssertNotNil(vm.notice)
    }

    func testUndo_abortedExternalEdit_doesNotSurfaceError() async {
        let vm = makeBoardViewModel(deleteSticky: ConfigurableDeleteStickyUseCase(),
                                    undo: ConfigurableUndoUseCase(.abortedExternalEdit))

        await vm.undo()

        XCTAssertNil(vm.error)
    }

    func testUndo_nothingToUndo_leavesNoticeNil() async {
        let vm = makeBoardViewModel(deleteSticky: ConfigurableDeleteStickyUseCase(),
                                    undo: ConfigurableUndoUseCase(.nothingToUndo))

        await vm.undo()

        XCTAssertNil(vm.notice)
    }

    /// On abort the VM reloads so the divergent on-disk board is shown immediately, rather than
    /// relying on the debounced `BoardStoreWatcher` (PR #78 review).
    func testUndo_abortedExternalEdit_reloadsBoard() async {
        let spyLoad = SpyLoadBoardViewStateUseCase()
        let vm = makeBoardViewModel(loadBoardViewState: spyLoad,
                                    deleteSticky: ConfigurableDeleteStickyUseCase(),
                                    undo: ConfigurableUndoUseCase(.abortedExternalEdit))

        await vm.undo()

        XCTAssertEqual(spyLoad.executeCount, 1)
    }

    func testUndo_nothingToUndo_doesNotReloadBoard() async {
        let spyLoad = SpyLoadBoardViewStateUseCase()
        let vm = makeBoardViewModel(loadBoardViewState: spyLoad,
                                    deleteSticky: ConfigurableDeleteStickyUseCase(),
                                    undo: ConfigurableUndoUseCase(.nothingToUndo))

        await vm.undo()

        XCTAssertEqual(spyLoad.executeCount, 0)
    }
}

// MARK: - Configurable stubs

private final class ConfigurableUndoUseCase: AsyncUseCase, @unchecked Sendable {
    private let outcome: UndoResponse

    init(_ outcome: UndoResponse) { self.outcome = outcome }

    func execute(_ request: UndoRequest) async throws -> UndoResponse { outcome }
}

private final class SpyLoadBoardViewStateUseCase: AsyncUseCase, @unchecked Sendable {
    private let count = Mutex(0)

    var executeCount: Int { count.withLock { $0 } }

    func execute(_ request: LoadBoardViewStateRequest) async throws -> BoardViewStateResponse {
        count.withLock { $0 += 1 }
        return stubBoardViewState()
    }
}

private final class ConfigurableDeleteStickyUseCase: AsyncUseCase, @unchecked Sendable {
    private let storedError = Mutex<(any Error)?>(nil)

    var error: (any Error)? {
        get { storedError.withLock { $0 } }
        set { storedError.withLock { $0 = newValue } }
    }

    func execute(_ request: DeleteStickyRequest) async throws -> BoardMutationResponse {
        if let error = storedError.withLock({ $0 }) { throw error }
        return stubBoardMutation()
    }
}
