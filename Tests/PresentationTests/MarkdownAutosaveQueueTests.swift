import XCTest
@testable import KanvasCore

/// Tests for `MarkdownAutosaveQueue` — the serialized, coalescing, durably-journaled autosave
/// channel that owns Markdown persistence off the editor view's lifecycle (tickets B817F0D2 +
/// 44C9D3C2).
///
/// The contract:
/// - A single enqueue persists its content; a burst coalesces to the *latest* text.
/// - A failed write is retried until it succeeds; a failure streak surfaces `onError` once.
/// - The text is journaled to disk *before* each write attempt and the journal is cleared on
///   success — so a pending edit survives an app quit/crash and is restored next launch.
/// - On give-up the disposition splits by error class: a deterministic failure clears the journal
///   and releases `hasPending`; a retainable failure keeps the journal, marks the card `stuck`
///   (`hasPending` stays true, surfaced via `unsavedEdits`), and offers manual retry/discard.
@MainActor
final class MarkdownAutosaveQueueTests: XCTestCase {

    private struct SaveError: Error {}

    /// Records every write and replays a scripted result sequence; once the script is
    /// exhausted it returns `defaultResult` (default `nil` = success, or a fixed error to
    /// simulate a permanent/deterministic failure).
    private final class WriteSpy {
        private(set) var calls: [(cardID: UUID, content: String)] = []
        private var scriptedResults: [(any Error)?]
        private let defaultResult: (any Error)?

        init(results: [(any Error)?] = [], thenAlways defaultResult: (any Error)? = nil) {
            scriptedResults = results
            self.defaultResult = defaultResult
        }

        func write(_ cardID: UUID, _ content: String) -> (any Error)? {
            calls.append((cardID, content))
            return scriptedResults.isEmpty ? defaultResult : scriptedResults.removeFirst()
        }
    }

    /// Records the order of card writes across attempts. A reference type so the `write` closure
    /// can accumulate; mutated only on the main actor by the queue (like the other spies here).
    private final class WriteLog {
        private(set) var cards: [UUID] = []
        func append(_ cardID: UUID) { cards.append(cardID) }
    }

    /// Records durable-journal interactions so a test can assert write-ahead + clear behavior.
    private final class JournalSpy {
        private(set) var saved: [(cardID: UUID, content: String, enqueuedAt: Date)] = []
        private(set) var cleared: [UUID] = []

        func journal(_ cardID: UUID, _ content: String, _ enqueuedAt: Date) {
            saved.append((cardID, content, enqueuedAt))
        }
        func clear(_ cardID: UUID) { cleared.append(cardID) }
    }

    private let cardID = UUID()

    // MARK: - enqueue

    func testEnqueue_persistsContent() async {
        let spy = WriteSpy()
        let queue = makeQueue(spy: spy)

        queue.enqueue(cardID: cardID, content: "hello")
        await queue.waitUntilIdle()

        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls.first?.content, "hello")
    }

    // MARK: - coalescing

    func testEnqueueBurst_coalescesToLatestTextOnly() async {
        let spy = WriteSpy()
        let queue = makeQueue(spy: spy)

        // Both enqueues run synchronously before the drain task body executes (no await
        // between them), so the first text is overwritten and never written.
        queue.enqueue(cardID: cardID, content: "first")
        queue.enqueue(cardID: cardID, content: "second")
        await queue.waitUntilIdle()

        XCTAssertEqual(spy.calls.map(\.content), ["second"])
    }

    // MARK: - retry

    func testFailedWrite_retriesUntilSuccess() async {
        // First two attempts fail; the third (script exhausted) succeeds.
        let spy = WriteSpy(results: [SaveError(), SaveError()])
        let queue = makeQueue(spy: spy)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()

        XCTAssertEqual(spy.calls.count, 3)
        XCTAssertTrue(spy.calls.allSatisfy { $0.content == "x" })
    }

    // MARK: - error surfacing

    func testFailureStreak_surfacesErrorExactlyOnce() async {
        var errorCount = 0
        let spy = WriteSpy(results: [SaveError(), SaveError()])
        let queue = makeQueue(spy: spy, onError: { _ in errorCount += 1 })

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()

        XCTAssertEqual(errorCount, 1)
    }

    func testDistinctCardFailures_eachSurfacesOnce() async {
        // A global failure-streak flag would swallow the second card's error; per-card tracking
        // surfaces each card's own first failure.
        var errorCount = 0
        let spy = WriteSpy(thenAlways: SaveError())
        let queue = makeQueue(spy: spy, onError: { _ in errorCount += 1 }, maxAttempts: 1)

        queue.enqueue(cardID: cardID, content: "a")
        queue.enqueue(cardID: UUID(), content: "b")
        await queue.waitUntilIdle()

        XCTAssertEqual(errorCount, 2)
    }

    // MARK: - give up

    func testFailure_givesUpAfterMaxAttempts() async {
        // A write that always fails must not spin forever.
        let spy = WriteSpy(thenAlways: SaveError())
        let queue = makeQueue(spy: spy, maxAttempts: 3)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()

        XCTAssertEqual(spy.calls.count, 3)
    }

    func testGiveUp_deterministicFailure_clearsGateAndJournal() async {
        // A deterministic failure (card deleted) must release `hasPending` so the editor's
        // external-rewrite gate (`!hasPendingSave`) unjams, and drop the journal entry.
        let spy = WriteSpy(thenAlways: SaveError())
        let journal = JournalSpy()
        let queue = makeQueue(spy: spy, journal: journal, isRetainable: { _ in false }, maxAttempts: 3)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()

        XCTAssertFalse(queue.hasPending(cardID))
        XCTAssertTrue(Set(queue.unsavedEdits().keys).isEmpty)
        XCTAssertEqual(journal.cleared.last, cardID)
    }

    func testGiveUp_retainableFailure_keepsStuckAndJournal() async {
        // A transient failure (disk full) must keep the edit: `hasPending` stays true, the card is
        // surfaced via `unsavedEdits`, and the journal entry is NOT cleared.
        let spy = WriteSpy(thenAlways: SaveError())
        let journal = JournalSpy()
        let queue = makeQueue(spy: spy, journal: journal, isRetainable: { _ in true }, maxAttempts: 3)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()

        XCTAssertTrue(queue.hasPending(cardID))
        XCTAssertEqual(Set(queue.unsavedEdits().keys), [cardID])
        XCTAssertFalse(journal.cleared.contains(cardID))
    }

    // MARK: - durable journal

    func testDrain_journalsBeforeWriting() async {
        let spy = WriteSpy()
        let journal = JournalSpy()
        let queue = makeQueue(spy: spy, journal: journal)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()

        // Write-ahead: the journal holds the text and the write ran with the same content.
        XCTAssertEqual(journal.saved.last?.content, "x")
        XCTAssertEqual(spy.calls.last?.content, "x")
    }

    func testSuccessfulWrite_clearsJournal() async {
        let journal = JournalSpy()
        let queue = makeQueue(spy: WriteSpy(), journal: journal)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()

        XCTAssertEqual(journal.cleared, [cardID])
    }

    // MARK: - restore

    func testRestore_reEnqueuesAndWrites() async {
        let spy = WriteSpy()
        let queue = makeQueue(spy: spy)

        queue.restore([(cardID: cardID, content: "recovered", enqueuedAt: Date(timeIntervalSince1970: 5))])
        await queue.waitUntilIdle()

        XCTAssertEqual(spy.calls.map(\.content), ["recovered"])
    }

    func testRestore_preservesEnqueuedAtWhenItStrandsAgain() async {
        // A restored entry that fails again keeps its original journal `enqueuedAt`, not "now".
        let spy = WriteSpy(thenAlways: SaveError())
        let originalAt = Date(timeIntervalSince1970: 5)
        let queue = makeQueue(spy: spy, isRetainable: { _ in true }, maxAttempts: 1)

        queue.restore([(cardID: cardID, content: "recovered", enqueuedAt: originalAt)])
        await queue.waitUntilIdle()

        XCTAssertEqual(queue.unsavedEdits()[cardID], originalAt)
    }

    // MARK: - retry / discard

    func testRetry_reattemptsStrandedWrite() async {
        // Fail until stuck, then let the retry succeed.
        let spy = WriteSpy(results: [SaveError(), SaveError(), SaveError()])
        let queue = makeQueue(spy: spy, isRetainable: { _ in true }, maxAttempts: 3)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()
        XCTAssertEqual(Set(queue.unsavedEdits().keys), [cardID])

        queue.retry(cardID: cardID)
        await queue.waitUntilIdle()

        XCTAssertTrue(Set(queue.unsavedEdits().keys).isEmpty)
        XCTAssertFalse(queue.hasPending(cardID))
    }

    func testDiscard_dropsStrandedEditAndClearsJournal() async {
        let spy = WriteSpy(thenAlways: SaveError())
        let journal = JournalSpy()
        let queue = makeQueue(spy: spy, journal: journal, isRetainable: { _ in true }, maxAttempts: 3)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()
        XCTAssertEqual(Set(queue.unsavedEdits().keys), [cardID])

        await queue.discard(cardID: cardID)

        XCTAssertTrue(Set(queue.unsavedEdits().keys).isEmpty)
        XCTAssertFalse(queue.hasPending(cardID))
        XCTAssertEqual(journal.cleared.last, cardID)
    }

    func testEnqueue_supersedesStrandedEdit() async {
        // Strand an edit, then a fresh edit for the same card must clear `stuck` and retry clean.
        let spy = WriteSpy(results: [SaveError(), SaveError(), SaveError()])
        let queue = makeQueue(spy: spy, isRetainable: { _ in true }, maxAttempts: 3)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()
        XCTAssertEqual(Set(queue.unsavedEdits().keys), [cardID])

        queue.enqueue(cardID: cardID, content: "fresh")
        await queue.waitUntilIdle()

        XCTAssertTrue(Set(queue.unsavedEdits().keys).isEmpty)
        XCTAssertEqual(spy.calls.last?.content, "fresh")
    }

    func testEnqueueDuringBackoff_resetsFailureStreakSoFirstFailureDoesNotGiveUp() async {
        // A card already at `maxAttempts - 1` consecutive failures (mid-backoff) receives a fresh
        // edit. The new edit must start a *clean* streak: its first failure must NOT immediately
        // give up (and must surface `onError`), proving `enqueue` reset `failureCounts`.
        var errorCount = 0
        // maxAttempts = 2: the first edit fails twice and gives up (→ stuck). With backoff parked,
        // a fresh edit arrives while the card sits at a failed streak. If the streak weren't reset,
        // the fresh edit's first failure (attempts would be 2) would hit the give-up gate at once.
        let spy = WriteSpy(thenAlways: SaveError())
        let queue = MarkdownAutosaveQueue(
            dependencies: MarkdownAutosaveQueue.Dependencies(
                write: { [spy] cardID, content in spy.write(cardID, content) },
                journal: { _, _, _ in },
                clearJournal: { _ in },
                isRetainable: { _ in true },
                onError: { _ in errorCount += 1 },
                onUnsavedChange: {}
            ),
            now: { Date(timeIntervalSince1970: 1_000) },
            // Park every backoff on a long, cancellable wait so the card stays mid-streak (not yet
            // re-injected) when the fresh edit arrives.
            backoffSleep: { _ in try? await Task.sleep(for: .seconds(3_600)) },
            backoff: .seconds(2),
            maxAttempts: 2
        )

        // First edit: fails once, then parks on a (held) backoff at attempts == 1 (= maxAttempts-1).
        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitForDrainPass()
        XCTAssertEqual(errorCount, 1, "first edit's first failure surfaced")
        XCTAssertTrue(queue.hasPending(cardID), "first edit is parked on its backoff timer")

        // Fresh edit supersedes the parked backoff. With the streak reset, its first failure is
        // attempt 1 — it surfaces `onError` again and parks for retry, rather than giving up.
        queue.enqueue(cardID: cardID, content: "fresh")
        await queue.waitForDrainPass()

        XCTAssertEqual(errorCount, 2, "fresh edit got a clean streak: its first failure surfaced")
        XCTAssertTrue(queue.unsavedEdits().isEmpty,
                      "fresh edit did not give up on its first failure (it is parked, not stranded)")
        XCTAssertTrue(queue.hasPending(cardID), "fresh edit is parked on a new backoff timer")
        XCTAssertEqual(spy.calls.last?.content, "fresh")
    }

    // MARK: - onUnsavedChange (mirror-drift guard)

    func testOnUnsavedChange_firesOnEveryStuckTransition() async {
        // The VM's observable `unsavedMarkdownEdits` mirror is only correct if every `stuck`
        // mutation notifies. Pin that a give-up→retain, a retry, and a discard each signal — so a
        // future 5th mutation site that forgets `onUnsavedChange()` breaks this test.
        var changeCount = 0
        let spy = WriteSpy(thenAlways: SaveError())
        let queue = makeQueue(spy: spy, isRetainable: { _ in true },
                              onUnsavedChange: { changeCount += 1 }, maxAttempts: 1)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()
        XCTAssertEqual(changeCount, 1, "give-up→retain must notify")

        queue.retry(cardID: cardID)
        await queue.waitUntilIdle()
        XCTAssertEqual(changeCount, 3, "retry (1) + the immediate re-strand (1) must each notify")

        await queue.discard(cardID: cardID)
        XCTAssertEqual(changeCount, 4, "discard must notify")
    }

    // MARK: - head-of-line blocking

    func testFailingCardBackoff_doesNotBlockHealthyCardWrite() async {
        // A failing card's retry backoff must not stall a healthy card's save: the failed card is
        // parked off the drain loop, so the loop keeps draining. The injected `backoffSleep` parks the
        // backoff (a long, cancellable wait) so the test can observe the healthy card landing while
        // the failing card is still waiting — the head-of-line guarantee.
        let failing = UUID()
        let healthy = UUID()
        let writes = WriteLog()
        let queue = MarkdownAutosaveQueue(
            dependencies: MarkdownAutosaveQueue.Dependencies(
                write: { [writes] cardID, _ -> (any Error)? in
                    writes.append(cardID)
                    // Fail `failing` only on its first write; its later retry (and `healthy`) succeed.
                    let isFirstFailingWrite = cardID == failing && writes.cards.filter { $0 == failing }.count == 1
                    return isFirstFailingWrite ? SaveError() : nil
                },
                journal: { _, _, _ in },
                clearJournal: { _ in },
                isRetainable: { _ in true },
                onError: { _ in },
                onUnsavedChange: {}
            ),
            now: { Date(timeIntervalSince1970: 1_000) },
            // Park the backoff on a long, cancellable wait so it stays pending across the drain pass.
            backoffSleep: { _ in try? await Task.sleep(for: .seconds(3_600)) },
            backoff: .seconds(2),
            maxAttempts: 3
        )

        queue.enqueue(cardID: failing, content: "a")
        queue.enqueue(cardID: healthy, content: "b")
        // Await only the drain pass — NOT the parked retry, which is still waiting out its backoff.
        await queue.waitForDrainPass()

        // The healthy card was written despite the failing card's backoff still being pending.
        XCTAssertTrue(writes.cards.contains(healthy), "healthy card drained past the pending backoff")
        XCTAssertTrue(queue.hasPending(failing), "the failing card is parked on its backoff timer")
        XCTAssertFalse(queue.hasPending(healthy), "the healthy card's write already landed")

        // A fresh edit cancels the parked backoff and re-queues now; this retry succeeds and settles.
        queue.enqueue(cardID: failing, content: "a")
        await queue.waitUntilIdle()
        XCTAssertFalse(queue.hasPending(failing))
    }

    // MARK: - hasPending

    func testHasPending_trueAfterEnqueue() async {
        let queue = makeQueue(spy: WriteSpy())

        // Synchronous: the drain task has not run yet (no await), so the edit is still owed.
        queue.enqueue(cardID: cardID, content: "x")
        XCTAssertTrue(queue.hasPending(cardID))

        await queue.waitUntilIdle()   // drain the started task so it does not outlive the test
    }

    func testHasPending_falseAfterSuccessfulDrain() async {
        let queue = makeQueue(spy: WriteSpy())

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()

        XCTAssertFalse(queue.hasPending(cardID))
    }

    // MARK: - flush

    func testFlush_awaitsQueuedWriteLandingBeforeReturning() async {
        // The editor's image-delete path enqueues any un-debounced draft, then `flush`es so the
        // autosave lands *before* the delete removes a reference — otherwise a still-queued snapshot
        // of the un-deleted body races the delete on the shared `mutate` (ticket 2A2784BE, PR #137).
        let spy = WriteSpy()
        let queue = makeQueue(spy: spy)

        queue.enqueue(cardID: cardID, content: "with-image")
        // Synchronous: the drain task body has not run yet, so the edit is still owed.
        XCTAssertTrue(queue.hasPending(cardID))

        await queue.flush(cardID: cardID)

        XCTAssertEqual(spy.calls.map(\.content), ["with-image"], "the queued write landed before flush returned")
        XCTAssertFalse(queue.hasPending(cardID), "no work is owed for the card after flush")
    }

    func testFlush_returnsImmediatelyForCleanCard() async {
        // A card the queue owes nothing must not block the caller.
        let spy = WriteSpy()
        let queue = makeQueue(spy: spy)

        await queue.flush(cardID: cardID)

        XCTAssertTrue(spy.calls.isEmpty, "flush triggered no write for a clean card")
        XCTAssertFalse(queue.hasPending(cardID))
    }

    func testFlush_doesNotHangOnStuckCard() async {
        // A card that gave up after a retainable failure (`stuck`) will never land on its own. `flush`
        // must return once the card is only `stuck`, not spin forever awaiting a write that won't come.
        let spy = WriteSpy(thenAlways: SaveError())
        let queue = makeQueue(spy: spy, isRetainable: { _ in true }, maxAttempts: 1)

        queue.enqueue(cardID: cardID, content: "x")
        await queue.waitUntilIdle()
        XCTAssertEqual(Set(queue.unsavedEdits().keys), [cardID], "the card is stranded (stuck)")

        // Would hang if `flush` awaited a stuck card; the test completing proves it returns.
        await queue.flush(cardID: cardID)

        XCTAssertEqual(Set(queue.unsavedEdits().keys), [cardID], "still stuck — flush did not clear it")
    }

    // MARK: - Helpers

    private func makeQueue(
        spy: WriteSpy,
        journal: JournalSpy = JournalSpy(),
        isRetainable: @escaping (any Error) -> Bool = { _ in false },
        onError: @escaping (any Error) -> Void = { _ in },
        onUnsavedChange: @escaping () -> Void = {},
        maxAttempts: Int = 5
    ) -> MarkdownAutosaveQueue {
        MarkdownAutosaveQueue(
            dependencies: MarkdownAutosaveQueue.Dependencies(
                write: { [spy] cardID, content in spy.write(cardID, content) },
                journal: { [journal] cardID, content, enqueuedAt in journal.journal(cardID, content, enqueuedAt) },
                clearJournal: { [journal] cardID in journal.clear(cardID) },
                isRetainable: isRetainable,
                onError: onError,
                onUnsavedChange: onUnsavedChange
            ),
            now: { Date(timeIntervalSince1970: 1_000) },
            backoff: .zero,
            maxAttempts: maxAttempts
        )
    }
}
