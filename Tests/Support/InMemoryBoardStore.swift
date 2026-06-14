import Foundation
@testable import KanvasCore

/// In-memory `BoardStoreProtocol` for exercising the real `BoardRepository` and the use cases over
/// it. `@unchecked Sendable` is safe here: mutation happens only on a test's serial flow, never
/// concurrently.
///
/// `init(initial:)` seeds a single active board (the common single-board case, mirroring the old
/// single-snapshot store). `init()` starts empty with no catalog — the fresh-install / migration
/// starting point. `legacy` can be set to exercise `migrateLegacyBoard()`.
final class InMemoryBoardStore: BoardStoreProtocol, @unchecked Sendable {
    private var catalog: BoardCatalogDTO?
    private var boards: [UUID: BoardSnapshotDTO] = [:]
    var legacy: BoardSnapshotDTO?
    private var template: BoardTemplateDTO?
    /// When set, the next `saveCatalog` throws (simulating a disk-full / permission failure) and
    /// resets the flag. Lets a test exercise a mid-operation persistence failure.
    var failNextSaveCatalog = false
    /// When set, `loadCatalog` throws `fileCorrupted` — a present-but-undecodable `catalog.json`,
    /// distinct from the absent case (`loadFailed`). Cleared by a successful `saveCatalog` (a valid
    /// write replaces the corrupt file). Lets a test exercise corrupt-catalog recovery.
    var corruptCatalog = false
    /// Board IDs whose snapshot is still listed by `listBoardSnapshotIDs()` but throws
    /// `fileCorrupted` on `load` — a present-but-undecodable `boards/<id>.json`. Lets a recovery
    /// test exercise per-record fail-open (skip a corrupt orphan, promote past a corrupt active)
    /// without fabricating a real malformed file.
    var corruptBoardIDs: Set<UUID> = []
    /// Board IDs whose `load` throws `loadFailed` (a non-decode fault) despite being listed —
    /// simulates a transient/unexpected read error. Recovery must *propagate* this (abort + retry
    /// next bootstrap), not drop the board, so its catch is narrowed to `fileCorrupted`.
    var loadFailingBoardIDs: Set<UUID> = []

    init(initial: BoardSnapshotDTO) {
        let id = initial.board.id
        boards[id] = initial
        catalog = BoardCatalogDTO(
            activeBoardID: id,
            boards: [BoardRefDTO(id: id, title: initial.board.title)]
        )
    }

    init() {}

    func loadCatalog() throws -> BoardCatalogDTO {
        if corruptCatalog { throw OperationError.fileCorrupted }
        guard let catalog else { throw OperationError.loadFailed }
        return catalog
    }

    func saveCatalog(_ catalog: BoardCatalogDTO) throws {
        if failNextSaveCatalog {
            failNextSaveCatalog = false
            throw OperationError.saveFailed
        }
        self.catalog = catalog
        corruptCatalog = false  // a successful write replaces the corrupt file with valid JSON
    }

    func load(boardID: UUID) throws -> BoardSnapshotDTO {
        if corruptBoardIDs.contains(boardID) { throw OperationError.fileCorrupted }
        if loadFailingBoardIDs.contains(boardID) { throw OperationError.loadFailed }
        guard let snapshot = boards[boardID] else { throw OperationError.loadFailed }
        return snapshot
    }

    func save(boardID: UUID, _ snapshot: BoardSnapshotDTO) throws { boards[boardID] = snapshot }

    func delete(boardID: UUID) throws { boards[boardID] = nil }

    func listBoardSnapshotIDs() throws -> [UUID] {
        boards.keys.sorted { $0.uuidString < $1.uuidString }
    }

    func loadLegacy() throws -> BoardSnapshotDTO? { legacy }

    func loadTemplate() throws -> BoardTemplateDTO? { template }

    func saveTemplate(_ template: BoardTemplateDTO) throws { self.template = template }

    /// No cross-process locking in tests — the in-memory store has a single serial flow, so just
    /// run the body. (The real `JSONBoardStore` takes an `flock` here.)
    func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T { try body() }

    // MARK: Test introspection

    /// Number of persisted board snapshots — lets a test assert a board's file was actually deleted.
    var storedBoardCount: Int { boards.count }

    /// Titles of every persisted snapshot — lets a recovery test assert which boards survived.
    var snapshotTitles: [String] { boards.values.map(\.board.title) }
}
