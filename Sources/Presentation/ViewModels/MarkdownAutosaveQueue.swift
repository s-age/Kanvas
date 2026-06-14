import Foundation

/// Serialized, coalescing, **durably-journaled** autosave channel for a card's Markdown notes.
///
/// `MarkdownEditorView`'s fire-and-forget autosave had two residual gaps once the
/// baseline-on-success fix (ticket 7CF1F5F1) landed:
///
/// 1. **Lost edit on view-disappear during a failed save.** Retry lived in the View
///    (the rollback re-dirtied the baseline so a *later* view event would re-flush), so
///    if the only in-flight save failed right as the view disappeared, nothing was left
///    to fire the retry and the edit was dropped.
/// 2. **No ordering guarantee for concurrent saves.** Two different-text saves were
///    unstructured `Task`s racing to the repository; the last write to land on disk
///    might not be the newest text.
///
/// This queue closes both by owning the write off the View's lifecycle (it lives on the
/// `BoardViewModel`, which outlives any one editor appearance):
///
/// - **Serialize** — a single drain loop writes one card at a time. For a given card this
///   gives a defined, coalesced write order (closes gap 2). Note the order *across* cards is
///   not FIFO — `pending` is a `Dictionary` and the loop pops `pending.first` (hash order) —
///   which is fine for autosave: each card's own text is still serialized and latest-wins.
///   The loop **never blocks on a retry backoff** — a failed card is parked off the loop (see
///   "Retry, bounded"), so one card's backoff can't stall a healthy card's save (no
///   head-of-line blocking).
/// - **Coalesce** — only the *latest* unsaved text per card is kept (`pending` is a
///   last-writer-wins dict), so a burst of edits collapses to one write of the final text
///   and stale intermediate writes are dropped.
/// - **Retry, bounded, per card** — a failed write is retried with exponential backoff,
///   independent of whether the editor view still exists (closes gap 1). The backoff wait
///   happens in a **per-card timer task off the drain loop** (`retrying`), not inside the loop:
///   the failed card is removed from the loop and re-injected into `pending` when its delay
///   elapses, so the loop keeps draining other cards meanwhile. After `maxAttempts` consecutive
///   failures the queue **gives up** on retrying that text in this session — but no longer
///   silently drops it (see durability below).
/// - **Surface failures once per card** — `onError` fires only on the *first* failure of a
///   card's streak, not on every retry, so a stuck disk doesn't spam the alert; two different
///   cards each surface their own first failure (the streak is tracked per card, not global).
///
/// **Durability (ticket 44C9D3C2).** The queue is backed by a per-card disk journal (a
/// write-ahead log on a substrate separate from the board store — no `flock`/undo):
///
/// - The drain loop **journals the text before attempting the real write** and **clears the
///   journal on success**, so a pending write survives an app quit/crash — on the next launch the
///   leftover entries are restored (`restore`) and the writes retried.
/// - On give-up the outcome depends on the error: a **deterministic** failure (`isRetainable`
///   false — e.g. the card was deleted, so `editCard` throws `notFound` every time) clears the
///   journal and releases `hasPending`, so a doomed write cannot spin forever or pin the editor's
///   external-rewrite gate shut. A **retainable** failure (disk full, lock contention) keeps the
///   journal entry and moves the card into `stuck`: `hasPending` stays true (the unsaved edit must
///   still block an external `markdown_set` clobber) and the card is surfaced via `unsavedEdits`
///   for a manual `retry`/`discard` (the editor banner shows the edit's `enqueuedAt`). The retained
///   entry is also auto-retried on the next launch.
///
/// `@MainActor` and single-actor by construction, so no `Mutex` is needed — `enqueue`, the drain
/// loop, and the per-card retry timer tasks all run on the main actor (the timers inherit the
/// actor context) and interleave only at `await` points.
@MainActor
final class MarkdownAutosaveQueue {

    /// An unsaved edit awaiting (or stranded after) persistence: the text plus when it entered the
    /// channel. `enqueuedAt` is the edit's "unsaved since …" timestamp — persisted to the journal
    /// and shown in the editor's Retry/Discard banner.
    private struct Edit: Sendable {
        let content: String
        let enqueuedAt: Date
    }

    /// The queue's owner-supplied seam: the six non-default closures that connect the queue to its
    /// persistence (`write`/`journal`/`clearJournal`), error policy (`isRetainable`), and the owner's
    /// observable state (`onError`/`onUnsavedChange`). Bundled into one value so the `init` takes a
    /// single dependency arg instead of six positional closures (no `function_parameter_count`
    /// disable). The deterministic tunables (`now`, `backoffSleep`, `backoff`, `maxAttempts`) stay
    /// as defaulted `init` args so a test can vary just one without restating the whole seam.
    struct Dependencies {
        /// Performs the persist. Returns the error on failure, or `nil` on success. Injected so
        /// the queue holds no use case directly and is unit-testable with a spy.
        let write: (UUID, String) async -> (any Error)?
        /// Write-ahead persist of the latest text (+ its `enqueuedAt`) to the durable journal, before
        /// the real write is attempted. Best-effort (its own failure is swallowed by the closure) —
        /// journaling must not block the real write.
        let journal: (UUID, String, Date) async -> Void
        /// Deletes a card's journal entry — after the real write lands, or when the user discards a
        /// stranded edit.
        let clearJournal: (UUID) async -> Void
        /// Whether a failed write is worth retaining for retry. `false` for a *deterministic* failure
        /// whose save target is gone (card deleted → `notFound`): retaining would pin the gate forever.
        /// `true` for a transient one (disk full, lock contention): the edit is real and recoverable.
        let isRetainable: (any Error) -> Bool
        /// Surfaces a persist failure to the owner. Called only on the first failure of a card's
        /// consecutive failing streak (see `failureCounts`) to avoid alert spam on retries.
        let onError: (any Error) -> Void
        /// Notifies the owner that the set of stranded (`stuck`) cards changed, so it can refresh the
        /// observable "unsaved edits" state that drives the editor's manual Retry/Discard banner.
        let onUnsavedChange: () -> Void
    }

    private let write: (UUID, String) async -> (any Error)?
    private let journal: (UUID, String, Date) async -> Void
    private let clearJournal: (UUID) async -> Void
    private let isRetainable: (any Error) -> Bool
    private let onError: (any Error) -> Void
    private let onUnsavedChange: () -> Void
    /// Clock stamping an edit's `enqueuedAt` the moment it enters the channel. Injected so the
    /// "unsaved since …" time is deterministic in tests.
    private let now: () -> Date
    /// Suspends a per-card retry timer for the backoff delay. Injected (defaults to `Task.sleep`)
    /// so a test can hold a retry open and prove a healthy card still drains meanwhile, or run
    /// retries without waiting. Named to disambiguate from `Task.sleep`. Lives off the drain loop,
    /// so it never blocks other cards' saves.
    private let backoffSleep: (Duration) async -> Void
    /// Base delay before retrying a failed write; the effective delay grows exponentially per
    /// consecutive failure (capped). Injectable (`.zero`) so tests run without waiting.
    private let backoff: Duration
    /// Consecutive failures (per card) after which the queue gives up retrying that text — so a
    /// deterministic failure cannot spin forever or pin `hasPending`.
    private let maxAttempts: Int

    /// Latest unsaved edit per card. Coalesces — a second `enqueue` for a card overwrites
    /// the first, so only the newest text is ever written.
    private var pending: [UUID: Edit] = [:]
    /// The card whose write is currently in flight (removed from `pending` but not yet
    /// persisted). Kept so `hasPending` stays true across the write — there is no window
    /// where a card with an unsaved edit looks clean.
    private var inFlight: UUID?
    /// The single drain loop, or `nil` when idle. Rooted here (not in the View), so the write
    /// continues after the editor disappears.
    private var drainTask: Task<Void, Never>?
    /// Per-card count of consecutive failures since the last success. Gates `onError` (surface
    /// only when a card's count crosses 0→1) and drives both the exponential backoff and the
    /// give-up after `maxAttempts`. Cleared on a successful write or on give-up. Per card so a
    /// second card's distinct failure is not swallowed by the first card's streak.
    private var failureCounts: [UUID: Int] = [:]
    /// Cards whose write gave up after a *retainable* failure: the edit is kept here (and on disk)
    /// for a manual `retry`/`discard` and an auto-retry next launch. Keeps `hasPending` true so a
    /// genuine unsaved edit still blocks an external rewrite.
    private var stuck: [UUID: Edit] = [:]
    /// Cards parked off the drain loop awaiting a backed-off retry, each mapped to its timer task.
    /// The failed edit is captured in the task; when the delay elapses the task re-injects it into
    /// `pending`. Keeps `hasPending` true during the backoff window so an external rewrite can't
    /// clobber a not-yet-persisted edit while it waits. A superseding `enqueue` cancels the timer.
    private var retrying: [UUID: Task<Void, Never>] = [:]

    init(
        dependencies: Dependencies,
        now: @escaping () -> Date = { Date() },
        backoffSleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        backoff: Duration = .seconds(2),
        maxAttempts: Int = 5
    ) {
        self.write = dependencies.write
        self.journal = dependencies.journal
        self.clearJournal = dependencies.clearJournal
        self.isRetainable = dependencies.isRetainable
        self.onError = dependencies.onError
        self.onUnsavedChange = dependencies.onUnsavedChange
        self.now = now
        self.backoffSleep = backoffSleep
        self.backoff = backoff
        self.maxAttempts = maxAttempts
    }

    /// Cancel any in-flight backoff timers so a dropped queue doesn't leave tasks waiting out their
    /// (possibly long) delay before the `weak self` no-ops them. `BoardViewModel` is app-lifetime so
    /// this effectively only matters for tests that create and drop short-lived queues.
    deinit {
        retrying.values.forEach { $0.cancel() }
    }

    /// Whether this card still has unsaved content the queue owes the disk — queued, mid-write, or
    /// stranded (`stuck`) after a retainable give-up. The editor uses this as its authoritative
    /// "buffer dirty?" signal so an external rewrite (`markdown_set`) never adopts over a
    /// not-yet-persisted local edit.
    func hasPending(_ cardID: UUID) -> Bool {
        pending[cardID] != nil || inFlight == cardID || retrying[cardID] != nil || stuck[cardID] != nil
    }

    /// Cards whose write gave up after a retainable failure and still hold an unsaved edit on disk,
    /// mapped to each edit's `enqueuedAt`. Surfaced to the user for a manual Retry/Discard banner
    /// ("unsaved since …").
    func unsavedEdits() -> [UUID: Date] {
        stuck.mapValues(\.enqueuedAt)
    }

    /// Record the latest text for a card and ensure the drain loop is running. Synchronous —
    /// callable from `onDisappear` and have the write outlive the view.
    func enqueue(cardID: UUID, content: String) {
        // A fresh edit supersedes any stranded one for this card — it gets a clean retry streak.
        if stuck.removeValue(forKey: cardID) != nil { onUnsavedChange() }
        // …and supersedes a pending backoff: drop the old edit's timer and queue the new text now.
        cancelRetry(cardID)
        // Reset the prior streak so the new edit truly starts clean: otherwise a card already at
        // `maxAttempts - 1` failures would give up on the *new* edit's very first failure (and the
        // `attempts == 1` gate would also swallow its `onError`).
        failureCounts[cardID] = nil
        pending[cardID] = Edit(content: content, enqueuedAt: now())
        startDrainIfNeeded()
    }

    /// Re-enqueue edits recovered from the durable journal at startup, retrying their writes and
    /// preserving each edit's original `enqueuedAt`. Skips a card already queued or in flight (a
    /// live edit supersedes the stale journal text).
    func restore(_ edits: [(cardID: UUID, content: String, enqueuedAt: Date)]) {
        for edit in edits
        where pending[edit.cardID] == nil && inFlight != edit.cardID && retrying[edit.cardID] == nil {
            pending[edit.cardID] = Edit(content: edit.content, enqueuedAt: edit.enqueuedAt)
        }
        startDrainIfNeeded()
    }

    /// Re-attempt a stranded card's write now (user pressed Retry). Moves it from `stuck` back to
    /// `pending` with a fresh streak, keeping its original `enqueuedAt`.
    func retry(cardID: UUID) {
        guard let edit = stuck.removeValue(forKey: cardID) else { return }
        onUnsavedChange()
        pending[cardID] = edit
        startDrainIfNeeded()
    }

    /// Drop a stranded card's unsaved edit (user pressed Discard): forget it and delete its journal
    /// entry, releasing `hasPending`.
    func discard(cardID: UUID) async {
        guard stuck.removeValue(forKey: cardID) != nil else { return }
        onUnsavedChange()
        await clearJournal(cardID)
    }

    private func startDrainIfNeeded() {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in await self?.drain() }
    }

    /// Drains `pending` one card at a time until empty. Journals each text before the write and
    /// clears the journal on success; a failed write is parked on an off-loop backoff timer (see
    /// `scheduleRetry`) so the loop never sleeps, and gives up after `maxAttempts` consecutive
    /// failures for a card.
    private func drain() async {
        // `defer` runs synchronously at function exit (no `await` between the empty-`pending`
        // check and here), so an `enqueue` cannot interleave and lose its wake-up: it either
        // sees a live `drainTask` and is picked up by the loop, or starts a fresh one.
        defer { drainTask = nil }
        while let (cardID, edit) = pending.first {
            pending.removeValue(forKey: cardID)
            inFlight = cardID
            // Write-ahead: persist the intent to disk *before* attempting the real write, so the
            // edit survives a crash mid-write. Best-effort; a journal failure must not block.
            await journal(cardID, edit.content, edit.enqueuedAt)
            let error = await write(cardID, edit.content)
            inFlight = nil
            if let error {
                await handleFailure(cardID: cardID, edit: edit, error: error)
            } else {
                failureCounts[cardID] = nil
                await clearJournal(cardID)
            }
        }
    }

    /// Records a failed attempt, surfaces the error once per card-streak, and either re-queues
    /// the edit for a backed-off retry or gives up once the card has failed `maxAttempts` times.
    private func handleFailure(cardID: UUID, edit: Edit, error: any Error) async {
        let attempts = (failureCounts[cardID] ?? 0) + 1
        failureCounts[cardID] = attempts
        if attempts == 1 { onError(error) }   // surface once per card's failure streak
        guard attempts < maxAttempts else {
            // Give up retrying this text in-session. Clear the streak so `hasPending` is no longer
            // pinned by `failureCounts`; the disposition of the edit depends on the error class.
            failureCounts[cardID] = nil
            // A newer edit arrived while failing → let it retry fresh; don't strand the old text.
            guard pending[cardID] == nil else { return }
            if isRetainable(error) {
                // Transient failure: keep the durable journal entry and surface for manual action.
                // `hasPending` stays true via `stuck`, so an external rewrite can't clobber it.
                stuck[cardID] = edit
                onUnsavedChange()
            } else {
                // Deterministic failure (no save target, e.g. card deleted): drop + release the
                // gate so an MCP `markdown_set` can re-seed the card again.
                await clearJournal(cardID)
            }
            return
        }
        // A newer edit arrived while this write was in flight → it's already queued and will drain
        // (and back off on its own failure); don't schedule a stale retry on top of it.
        guard pending[cardID] == nil else { return }
        // Park the failed edit off the drain loop on a backed-off timer, so the loop is free to keep
        // draining healthy cards instead of sleeping (no head-of-line blocking). `hasPending` stays
        // true via `retrying` for the whole backoff window, so an external rewrite can't clobber it.
        scheduleRetry(cardID: cardID, edit: edit, delay: backoffDelay(forAttempt: attempts))
    }

    /// Parks a failed edit on a per-card backoff timer off the drain loop. When the delay elapses
    /// the timer re-injects the edit into `pending` and restarts the loop. A prior timer for the
    /// card is cancelled first so only the latest failed edit is ever re-injected.
    private func scheduleRetry(cardID: UUID, edit: Edit, delay: Duration) {
        retrying[cardID]?.cancel()
        // Capture `backoffSleep` directly (not through `self`) and hold `self` weakly, so the timer
        // never retains the queue while it waits out the backoff — a queue dropped during the window
        // must be free to deallocate, not pinned alive until the delay elapses.
        let backoffSleep = self.backoffSleep
        retrying[cardID] = Task { [weak self] in
            await backoffSleep(delay)
            // A superseding `enqueue` cancels the timer; bail rather than re-inject stale text.
            guard !Task.isCancelled, let self else { return }
            self.reinjectRetry(cardID: cardID, edit: edit)
        }
    }

    /// Moves a backed-off edit from `retrying` back into `pending` and wakes the drain loop — unless
    /// a newer edit already superseded it (then the timer was cancelled / the slot is taken).
    private func reinjectRetry(cardID: UUID, edit: Edit) {
        guard retrying.removeValue(forKey: cardID) != nil else { return }
        if pending[cardID] == nil { pending[cardID] = edit }
        startDrainIfNeeded()
    }

    /// Cancels and forgets a card's pending backoff timer (a fresh edit superseded it).
    private func cancelRetry(_ cardID: UUID) {
        retrying.removeValue(forKey: cardID)?.cancel()
    }

    /// Exponential backoff: `backoff × 2^(attempt-1)`, capped at 16× so a long streak settles
    /// at a steady interval rather than growing unbounded. `.zero` base stays zero (tests).
    private func backoffDelay(forAttempt attempt: Int) -> Duration {
        backoff * (1 << min(attempt - 1, 4))
    }

    /// Awaits this card's queued/in-flight/retrying write fully landing on disk before returning, so
    /// a caller that must serialize a *non-queue* write after the autosave (the editor's image delete,
    /// which removes a reference from the persisted body) cannot have its write clobbered by a later
    /// autosave snapshot of the un-deleted body racing the same `mutate`. Drives the loop and any
    /// parked backoff retry for *this* card to completion, looping because a retry re-injects into
    /// `pending` and may restart the loop. A `stuck` card (gave up after a retainable failure) is
    /// deliberately *not* awaited — it will never land on its own, and the editor's external-rewrite
    /// gate already treats `stuck` as dirty — so this returns once the card is only `stuck` (or clean),
    /// never hanging on an unrecoverable edit. The caller then issues its write against a baseline the
    /// queue is no longer about to overwrite.
    func flush(cardID: UUID) async {
        while pending[cardID] != nil || inFlight == cardID || retrying[cardID] != nil {
            await drainTask?.value
            await retrying[cardID]?.value
        }
    }

    /// Awaits the current drain loop pass only (not any scheduled backoff retries) — for tests that
    /// need to observe state right after the synchronous pass while a retry is still parked.
    func waitForDrainPass() async {
        await drainTask?.value
    }

    /// Awaits the queue going fully idle — the drain loop *and* every parked backoff retry, looping
    /// until no work remains (a retry re-injects into `pending` and may restart the loop). For
    /// deterministic tests only (`@testable` access). With a non-returning injected `backoffSleep`
    /// this would never settle, so a test holding a retry open must use `waitForDrainPass` instead.
    func waitUntilIdle() async {
        while drainTask != nil || !retrying.isEmpty {
            await drainTask?.value
            for task in Array(retrying.values) { await task.value }
        }
    }
}
