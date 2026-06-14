import Synchronization
import XCTest
@testable import KanvasCore

/// Pins the split of once-per-launch *writing* maintenance out of the read-only `load()` so the
/// store-watcher refresh can never trigger a write (ticket 7935A21E). The orphan-asset GC deletes
/// files and the Markdown-journal restore re-enqueues saves — both must run only from
/// `performStartupMaintenance()`, never from `load()`.
@MainActor
final class BoardViewModelStartupMaintenanceTests: XCTestCase {

    func testLoad_doesNotSweepOrphanedAssets() async {
        let sweep = SpySweepOrphanedImageAssets()
        let vm = makeBoardViewModel(sweepOrphans: sweep)

        await vm.load()

        XCTAssertEqual(sweep.executeCount, 0)
    }

    func testLoad_doesNotRestoreMarkdownJournal() async {
        let journalList = SpyListMarkdownJournal()
        let vm = makeBoardViewModel(journalList: journalList)

        await vm.load()

        XCTAssertEqual(journalList.executeCount, 0)
    }

    func testPerformStartupMaintenance_sweepsOrphanedAssets() async {
        let sweep = SpySweepOrphanedImageAssets()
        let vm = makeBoardViewModel(sweepOrphans: sweep)

        await vm.performStartupMaintenance()

        XCTAssertEqual(sweep.executeCount, 1)
    }

    func testPerformStartupMaintenance_restoresMarkdownJournal() async {
        let journalList = SpyListMarkdownJournal()
        let vm = makeBoardViewModel(journalList: journalList)

        await vm.performStartupMaintenance()

        XCTAssertEqual(journalList.executeCount, 1)
    }

    func testPerformStartupMaintenance_runsSweepOncePerLaunch() async {
        let sweep = SpySweepOrphanedImageAssets()
        let vm = makeBoardViewModel(sweepOrphans: sweep)

        await vm.performStartupMaintenance()
        await vm.performStartupMaintenance()

        XCTAssertEqual(sweep.executeCount, 1)
    }

    func testPerformStartupMaintenance_restoresMarkdownJournalOncePerLaunch() async {
        let journalList = SpyListMarkdownJournal()
        let vm = makeBoardViewModel(journalList: journalList)

        await vm.performStartupMaintenance()
        await vm.performStartupMaintenance()

        XCTAssertEqual(journalList.executeCount, 1)
    }

    func testPerformStartupMaintenance_restoreRetriesAfterAFailedListRead() async {
        // A failed journal read (the store couldn't enumerate its directory — logged there) must NOT
        // flip the once-per-launch guard, so a later maintenance pass retries rather than silently
        // skipping restore for the whole session (ticket 7DA7C85F).
        let journalList = SpyListMarkdownJournal()
        journalList.failNextRead = true
        let vm = makeBoardViewModel(journalList: journalList)

        await vm.performStartupMaintenance()   // first read throws → guard stays unset
        await vm.performStartupMaintenance()    // retries, succeeds, flips the guard

        XCTAssertEqual(journalList.executeCount, 2)
    }
}

// MARK: - Spies
//
// A `final class` whose only stored property is a `Mutex` (itself `Sendable`) conforms to `Sendable`
// outright — no `@unchecked` needed.

private final class SpySweepOrphanedImageAssets: SweepOrphanedImageAssetsUseCase, Sendable {
    private let count = Mutex(0)
    var executeCount: Int { count.withLock { $0 } }
    func execute() async throws { count.withLock { $0 += 1 } }
}

private final class SpyListMarkdownJournal: ListMarkdownJournalUseCase, Sendable {
    private let state = Mutex((count: 0, failNext: false))
    var executeCount: Int { state.withLock { $0.count } }
    /// When set, the next `execute()` throws once (then clears) — models the journal store failing
    /// to enumerate its directory, so the restore aborts and must stay retryable.
    var failNextRead: Bool {
        get { state.withLock { $0.failNext } }
        set { state.withLock { $0.failNext = newValue } }
    }
    func execute() async throws -> [PendingMarkdownEditResponse] {
        try state.withLock {
            $0.count += 1
            if $0.failNext { $0.failNext = false; throw OperationError.loadFailed }
        }
        return []
    }
}
