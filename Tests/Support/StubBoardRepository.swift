import Foundation
@testable import KanvasCore

/// Minimal `BoardRepositoryProtocol` for constructing Domain Services in **pure-transform** unit
/// tests. Those tests call the gerund transforms directly on the concrete service and never reach
/// the repository, so the stub only needs to satisfy the protocol. `mutate` / `mutateBoard` echo a
/// single held `BoardState`, so a Service's imperative verb can also be exercised when a test wants
/// to. For full read-modify-write / undo / catalog behaviour use the real `BoardRepository` over
/// `InMemoryBoardStore` instead (see the use-case tests).
///
/// `@unchecked Sendable` is safe here: mutation happens only on a test's serial flow.
final class StubBoardRepository: BoardRepositoryProtocol, @unchecked Sendable {
    private var state: BoardState
    /// When set, `loadBoard` / `loadAllBoardStates` throw this instead of echoing `state` — lets a
    /// test exercise the **transient-fault** abort path (a non-decode error propagates whole).
    var loadBoardError: (any Error)?
    /// Board ids `loadAllBoardStates` reports as undecodable in its `unreadableBoardIDs` (per-record
    /// fail-open) — lets a test exercise the "a snapshot won't decode is skipped, not thrown" path
    /// distinct from `loadBoardError`'s whole-list throw.
    var unreadableBoardIDs: [UUID] = []
    /// How many times `mutate` ran — lets a test assert a batch op opens the persistence boundary
    /// exactly **once** (one flock + read-modify-write + undo entry), the core of ticket 4FF14DCF.
    private(set) var mutateCallCount = 0

    init(state: BoardState = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])) {
        self.state = state
    }

    func loadActiveBoard() throws -> BoardState { state }
    func loadActiveBoardWithCatalog() throws -> ActiveBoardSnapshot {
        ActiveBoardSnapshot(state: state, boards: [state.board], activeBoardID: state.board.id)
    }
    func saveActiveBoard(_ newState: BoardState) throws { state = newState }

    func mutate(_ transform: @Sendable (BoardState) throws -> BoardState) throws -> BoardState {
        mutateCallCount += 1
        state = try transform(state)
        return state
    }

    func mutateBoard(id: UUID, _ transform: @Sendable (BoardState) throws -> BoardState) throws -> BoardState {
        state = try transform(state)
        return state
    }

    func undo() throws -> UndoOutcome { .nothingToUndo }
    func listBoards() throws -> BoardCatalog { BoardCatalog(boards: [state.board], activeBoardID: state.board.id) }
    func loadBoard(id: UUID) throws -> BoardState {
        if let loadBoardError { throw loadBoardError }
        return state
    }
    func loadAllBoardStates() throws -> (states: [BoardState], unreadableBoardIDs: [UUID]) {
        if let loadBoardError { throw loadBoardError }
        return (states: [state], unreadableBoardIDs: unreadableBoardIDs)
    }
    func switchActiveBoard(to id: UUID) throws -> BoardState { state }
    func insertBoard(_ newState: BoardState,
                     resolvingCatalog: @Sendable (BoardCatalog) throws -> BoardCatalog) throws -> BoardState {
        // Exercise the injected decision so a Service wiring the wrong resolver is observable, then
        // echo the single held state (this stub keeps no multi-board catalog).
        _ = try resolvingCatalog(BoardCatalog(boards: [state.board], activeBoardID: state.board.id))
        state = newState
        return state
    }
    func renameBoard(id: UUID, title: String) throws -> (boards: [Board], activeBoardID: UUID?) {
        ([state.board], state.board.id)
    }
    func deleteBoard(id: UUID,
                     resolvingCatalog: @Sendable (BoardCatalog) throws -> BoardCatalog) throws -> BoardState {
        // Exercise the injected decision so a Service wiring the wrong resolver is observable, then
        // echo the single held state (this stub keeps no multi-board catalog).
        _ = try resolvingCatalog(BoardCatalog(boards: [state.board], activeBoardID: state.board.id))
        return state
    }
    func migrateLegacyBoard(
        resolvingCatalog: @Sendable (Board, BoardCatalog) throws -> BoardCatalog
    ) throws -> BoardState? { nil }
    func recoverOrphanedBoards(
        resolvingCatalog: @Sendable (BoardCatalog) throws -> BoardCatalog
    ) throws -> BoardState? { nil }
    func loadTemplate() throws -> BoardTemplate { .default }
    func saveTemplate(_ template: BoardTemplate) throws {}
}

/// Minimal `ImageAssetRepositoryProtocol` for constructing `CanvasImageService` in pure-transform
/// tests (which never touch the asset bytes). Backed by an in-memory dictionary so an exercised
/// `add` / `loadImageData` round-trips.
final class StubImageAssetRepository: ImageAssetRepositoryProtocol, @unchecked Sendable {
    private var assets: [UUID: Data] = [:]
    /// What `assetIDs(modifiedBefore:)` reports — the GC's candidate set. Set directly by a test so
    /// the grace/mtime filtering (covered against the real `FileImageAssetStore`) need not be
    /// reproduced here; this isolates the service's reachability + subtraction logic.
    var sweepableIDs: Set<UUID> = []
    /// Records the cutoff the service passed, so a test can assert `now - gracePeriod`.
    private(set) var receivedCutoff: Date?
    /// Records every `delete` so a test can assert exactly which assets were reclaimed.
    private(set) var deletedAssetIDs: [UUID] = []
    /// Asset IDs whose `delete` throws — lets a test exercise the GC's per-file failure path
    /// (a locked / unpermissioned asset) and assert it is reported, not silently swallowed.
    var failingDeletes: Set<UUID> = []
    /// When set, `assetIDs(modifiedBefore:)` throws it — lets a test exercise the GC's
    /// candidate-listing failure path (the directory scan failing) and assert it is logged.
    var candidateListError: (any Error)?

    func save(assetID: UUID, data: Data) throws { assets[assetID] = data }
    func load(assetID: UUID) throws -> Data {
        guard let data = assets[assetID] else { throw OperationError.loadFailed }
        return data
    }
    func delete(assetID: UUID) throws {
        if failingDeletes.contains(assetID) { throw OperationError.loadFailed }
        assets[assetID] = nil
        deletedAssetIDs.append(assetID)
    }
    func assetIDs(modifiedBefore cutoff: Date) throws -> Set<UUID> {
        receivedCutoff = cutoff
        if let candidateListError { throw candidateListError }
        return sweepableIDs
    }
}
