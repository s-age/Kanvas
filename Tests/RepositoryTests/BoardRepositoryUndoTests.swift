import XCTest
@testable import KanvasCore

/// Undo is implemented as a bounded ring of undo entries (each pairing a pre-mutation snapshot
/// with the post-mutation snapshot this process wrote) recorded inside `BoardRepository.mutate`.
/// These tests pin that mechanism: a mutation is reversible, the history is capped at five, a
/// no-op mutation consumes no slot, an empty history is reported as `.nothingToUndo`, and — the
/// divergence guard (ticket 875C3208) — an undo aborts (`.abortedExternalEdit`) without clobbering
/// a board the MCP server edited between the mutation and the ⌘Z. The three-way `UndoOutcome`
/// (ticket D1436DAB) is what lets these assertions tell "nothing to undo" apart from "aborted",
/// which the former `BoardState?` collapsed into one `nil`.
///
/// Mutations append **columns** (a snapshot-authoritative field) rather than renaming the board:
/// `board.title` is catalog-authoritative and reconciled away on the cross-process reload inside
/// `mutate`, so a title set via `mutate` would not survive — production renames go through
/// `renameBoard`, never `mutate`.
final class BoardRepositoryUndoTests: XCTestCase {

    private var store: InMemoryBoardStore!
    private var repository: BoardRepository!

    override func setUp() {
        super.setUp()
        store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(BoardState.empty(title: "Board")))
        repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
    }

    override func tearDown() {
        repository = nil
        store = nil
        super.tearDown()
    }

    /// Appends one column titled `title`; each call yields a state distinct from the last, so the
    /// undo ring records a distinct pre-image per mutation.
    private func appendingColumn(_ title: String) -> @Sendable (BoardState) -> BoardState {
        { state in
            var next = state
            next.columns.append(
                Column(boardID: state.board.id, title: title, sortIndex: next.columns.count)
            )
            return next
        }
    }

    // MARK: - undo

    func testUndo_afterSingleMutation_restoresPreviousState() async throws {
        _ = try await repository.mutate(appendingColumn("c1"))

        let outcome = try await repository.undo()

        XCTAssertEqual(outcome.restoredState?.columns.count, 0)
    }

    func testUndo_withEmptyHistory_reportsNothingToUndo() async throws {
        let outcome = try await repository.undo()

        XCTAssertEqual(outcome, .nothingToUndo)
    }

    func testUndo_retainsAtMostFiveLevels() async throws {
        // Six distinct mutations push six pre-states, but only the latest five are kept.
        for index in 1...6 {
            _ = try await repository.mutate(appendingColumn("c\(index)"))
        }

        for _ in 0..<5 { _ = try await repository.undo() }
        let sixth = try await repository.undo()

        XCTAssertEqual(sixth, .nothingToUndo)
    }

    func testUndo_afterFiveLevelOverflow_stopsAtOldestRetainedState() async throws {
        // After six mutations the oldest retained pre-state is the one before the 2nd mutation:
        // a single column ("c1").
        for index in 1...6 {
            _ = try await repository.mutate(appendingColumn("c\(index)"))
        }

        var last: UndoOutcome = .nothingToUndo
        for _ in 0..<5 { last = try await repository.undo() }

        XCTAssertEqual(last.restoredState?.columns.map(\.title), ["c1"])
    }

    func testMutate_noOpChange_recordsNoUndoEntry() async throws {
        // A transform that returns an unchanged state must not consume an undo slot.
        _ = try await repository.mutate { $0 }

        let undone = try await repository.undo()
        XCTAssertEqual(undone, .nothingToUndo)
    }

    // MARK: - undo divergence (intervening external write)

    /// Simulates the MCP server (a separate process sharing the store) appending a column to the
    /// given board's snapshot on disk — an edit the running app's per-process undo ring never saw.
    private func writeExternalColumn(_ title: String, to state: BoardState) throws {
        var external = state
        external.columns.append(
            Column(boardID: state.board.id, title: title, sortIndex: external.columns.count)
        )
        try store.save(boardID: state.board.id, BoardSnapshotMapper.toDTO(external))
    }

    func testUndo_whenDiskDivergedFromRecordedPostState_reportsAbortedExternalEdit() async throws {
        let mutated = try await repository.mutate(appendingColumn("c1"))
        try writeExternalColumn("mcp", to: mutated)  // MCP edits the same board before the ⌘Z

        let outcome = try await repository.undo()

        XCTAssertEqual(outcome, .abortedExternalEdit)
    }

    func testUndo_whenDiskDivergedFromRecordedPostState_leavesForeignEditOnDisk() async throws {
        let mutated = try await repository.mutate(appendingColumn("c1"))
        try writeExternalColumn("mcp", to: mutated)

        _ = try await repository.undo()  // must not write the stale pre-image back

        let onDisk = try await repository.loadActiveBoard()
        XCTAssertEqual(onDisk.columns.map(\.title), ["c1", "mcp"])
    }

    func testUndo_afterDivergenceAbort_subsequentUndoReportsNothingToUndo() async throws {
        _ = try await repository.mutate(appendingColumn("c1"))
        let second = try await repository.mutate(appendingColumn("c2"))
        try writeExternalColumn("mcp", to: second)

        _ = try await repository.undo()         // diverged → aborts, drops the stale ring
        let again = try await repository.undo()

        XCTAssertEqual(again, .nothingToUndo)
    }

    /// The case that proves both `before` AND `after` must be stored (a single-snapshot ring would
    /// regress here). A foreign edit lands **between** two of this process's mutations: it rides
    /// into `c2`'s pre-image (`entry2.before == [c1, mcp]`) while `entry1.after` stays `[c1]`.
    /// Undoing `c2` matches its own post-state on disk and succeeds, restoring `[c1, mcp]`.
    func testUndo_midSequenceForeignEdit_firstUndoRestoresStateIncludingForeignEdit() async throws {
        let first = try await repository.mutate(appendingColumn("c1"))
        try writeExternalColumn("mcp", to: first)
        _ = try await repository.mutate(appendingColumn("c2"))

        let outcome = try await repository.undo()

        XCTAssertEqual(outcome.restoredState?.columns.map(\.title), ["c1", "mcp"])
    }

    /// Continuation of the mid-sequence case: a *second* undo would restore `c1`'s bare pre-image
    /// `[c1]`, dropping the foreign `mcp` column embedded in `entry2.before`. The divergence guard
    /// (disk `[c1, mcp]` ≠ `entry1.after` `[c1]`) catches it and aborts.
    func testUndo_midSequenceForeignEdit_secondUndoAbortsPreservingForeignEdit() async throws {
        let first = try await repository.mutate(appendingColumn("c1"))
        try writeExternalColumn("mcp", to: first)
        _ = try await repository.mutate(appendingColumn("c2"))

        _ = try await repository.undo()          // restores [c1, mcp]
        let secondUndo = try await repository.undo()

        XCTAssertEqual(secondUndo, .abortedExternalEdit)
    }

    /// When the active board's snapshot won't decode, `exclusive` leaves `current` nil — undo
    /// cannot compare for divergence and must fall through to restoring the recorded pre-image
    /// (preserving the pre-divergence-guard recovery behaviour).
    func testUndo_whenActiveSnapshotUnreadable_fallsThroughToRestore() async throws {
        let mutated = try await repository.mutate(appendingColumn("c1"))
        store.corruptBoardIDs = [mutated.board.id]

        let outcome = try await repository.undo()

        XCTAssertEqual(outcome.restoredState?.columns.count, 0)
    }
}

private extension UndoOutcome {
    /// The restored `BoardState` when this is `.restored`, else `nil` — so a test can assert on the
    /// reverted board while `XCTAssertEqual(outcome, .nothingToUndo/.abortedExternalEdit)` covers
    /// the two non-restoring cases.
    var restoredState: BoardState? {
        if case .restored(let state) = self { return state }
        return nil
    }
}

// The in-memory `BoardStoreProtocol` lives in `Tests/Support/InMemoryBoardStore.swift`.
