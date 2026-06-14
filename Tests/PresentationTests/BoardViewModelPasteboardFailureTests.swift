import XCTest
@testable import KanvasCore

/// Pins `BoardViewModel.reportPasteboardWriteFailure` → the fire-and-forget diagnostics use case
/// (ticket 8E857E6F). Presentation cannot reach the diagnostics capability port directly, so a failed
/// copy-to-pasteboard write must route through this use case to reach Console instead of being a
/// silent no-op. The copy button calls this on the `setString == false` branch.
@MainActor
final class BoardViewModelPasteboardFailureTests: XCTestCase {

    func testReportPasteboardWriteFailure_invokesUseCaseOnce() async {
        let spy = SpyReportPasteboardWriteFailure()
        let vm = makeBoardViewModel(reportPasteboardWriteFailure: spy)

        vm.reportPasteboardWriteFailure(label: "card ID")

        XCTAssertEqual(spy.executeCallCount, 1)
    }

    func testReportPasteboardWriteFailure_forwardsLabel() async {
        let spy = SpyReportPasteboardWriteFailure()
        let vm = makeBoardViewModel(reportPasteboardWriteFailure: spy)

        vm.reportPasteboardWriteFailure(label: "card ID")

        XCTAssertEqual(spy.lastLabel, "card ID")
    }
}

/// Call-counting spy for the pasteboard-write-failure diagnostic. Mutation is confined to a test's
/// serial main-actor flow, so `@unchecked Sendable` is acceptable on this test double.
private final class SpyReportPasteboardWriteFailure: ReportPasteboardWriteFailureUseCase, @unchecked Sendable {
    private(set) var executeCallCount = 0
    private(set) var lastLabel: String?

    func execute(label: String) {
        executeCallCount += 1
        lastLabel = label
    }
}
