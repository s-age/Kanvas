import XCTest
@testable import KanvasCore

/// Pins `BoardViewModel.loadImageData`'s error → `CanvasImageLoad` mapping — the behavioural core of
/// ticket 37B774CD. The canvas keys terminal-vs-transient negative-caching off this distinction, so a
/// refactor that re-collapses it would silently reintroduce the permanent-placeholder bug.
@MainActor
final class BoardViewModelImageLoadTests: XCTestCase {

    func testLoadImageData_success_returnsLoadedWithBytes() async {
        let bytes = Data([1, 2, 3])
        let vm = makeBoardViewModel(loadData: ThrowingLoadImageData(result: .success(bytes)))

        guard case .loaded(let data) = await vm.loadImageData(assetID: UUID()) else {
            return XCTFail("Expected .loaded")
        }
        XCTAssertEqual(data, bytes)
    }

    func testLoadImageData_loadFailed_returnsUnavailable() async {
        // `loadFailed` is the store's genuine-absence signal → terminal (the canvas negative-caches it).
        let vm = makeBoardViewModel(loadData: ThrowingLoadImageData(result: .failure(OperationError.loadFailed)))

        guard case .unavailable = await vm.loadImageData(assetID: UUID()) else {
            return XCTFail("Expected .unavailable for loadFailed")
        }
    }

    func testLoadImageData_otherError_returnsTransientFailure() async {
        // Any non-`loadFailed` error (a read fault, a directory, EACCES) is treated as transient so
        // the canvas retries rather than pinning the placeholder on a recoverable blip.
        let vm = makeBoardViewModel(loadData: ThrowingLoadImageData(result: .failure(OperationError.saveFailed)))

        guard case .transientFailure = await vm.loadImageData(assetID: UUID()) else {
            return XCTFail("Expected .transientFailure for a non-loadFailed error")
        }
    }

    func testLoadImageData_cancellation_returnsTransientFailure() async {
        // A cancelled `.task`-bound fetch is "no longer wanted", not a terminal failure — retry later.
        let vm = makeBoardViewModel(loadData: ThrowingLoadImageData(result: .failure(CancellationError())))

        guard case .transientFailure = await vm.loadImageData(assetID: UUID()) else {
            return XCTFail("Expected .transientFailure for cancellation")
        }
    }
}

// MARK: - Configurable load stub

private struct ThrowingLoadImageData: LoadImageDataUseCase, @unchecked Sendable {
    let result: Result<Data, Error>
    func execute(assetID: UUID) async throws -> Data { try result.get() }
}
