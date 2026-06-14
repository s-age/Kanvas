import Foundation

/// File-backed multi-board store. Layout under the injected base directory:
/// - `catalog.json`       — the `BoardCatalogDTO` index
/// - `boards/<id>.json`   — one `BoardSnapshotDTO` per board
/// - `board.json`         — legacy single-board file, read only for one-time migration
final class JSONBoardStore: BoardStoreProtocol, Sendable {
    private let directory: URL
    /// Cross-process lock guarding the whole store directory (see `withExclusiveAccess`).
    private let fileLock: FileLock
    /// Runs the blocking `flock` + JSON I/O off the cooperative pool (see `withExclusiveAccess`).
    private let ioQueue: BlockingIOQueue
    /// Records every file we write so `BoardStoreWatcher` can skip the self-echo reload our own
    /// atomic saves trigger (ticket 5BC2FF20). Shared with the watcher via DI.
    private let writeLedger: BoardStoreWriteLedger
    /// Names the file + decode error when a snapshot/catalog won't parse — see `decode`. The
    /// `fileCorrupted` it raises is detail-less by the time the Repository owns the recovery
    /// decision, so the *which-file/which-key* signal must be captured here, at the only point it
    /// still exists. Same sink the Repository observes through (no second `os.Logger` in the store).
    private let diagnostics: any DiagnosticsSinkProtocol

    init(directory: URL, writeLedger: BoardStoreWriteLedger, diagnostics: any DiagnosticsSinkProtocol) {
        self.directory = directory
        self.writeLedger = writeLedger
        self.diagnostics = diagnostics
        // The lock file lives at the store root; ensure the directory exists before opening it
        // (callers may construct the store before any save has lazily created the tree). Don't
        // swallow a failure here: a missing store root makes every later `flock`/save fail, so
        // surface it through the same sink the Repository observes — the DI layer no longer logs
        // this (it does no I/O of its own), so this is the one place the signal still exists.
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            diagnostics.emit("board store: could not create the store root; persistence will fail",
                             privateDetail: "\(directory.path): \(error)", level: .error)
        }
        fileLock = FileLock(path: directory.appendingPathComponent(".kanvas.lock"))
        // `.userInitiated`: the board store backs interactive edits (a sticky drag's `mutate`
        // repaints the canvas), so its offloaded flock+I/O must not run below the awaiting UI.
        ioQueue = BlockingIOQueue(label: "com.kanvas.boardstore.io", qos: .userInitiated)
    }

    func withExclusiveAccess<T: Sendable>(_ body: @Sendable @escaping () throws -> T) async throws -> T {
        // The whole critical section — flock acquire → body's reload/transform/save → flock release
        // — runs on the dedicated serial queue, so the cooperative-pool thread that called us is
        // released (suspended) for the duration rather than parked on the blocking lock.
        try await ioQueue.run { try self.fileLock.withExclusiveLock(body) }
    }

    private var catalogURL: URL { directory.appendingPathComponent("catalog.json") }
    private var legacyURL: URL { directory.appendingPathComponent("board.json") }
    private var templateURL: URL { directory.appendingPathComponent("template.json") }
    private var boardsDirectory: URL { directory.appendingPathComponent("boards", isDirectory: true) }

    private func boardURL(_ boardID: UUID) -> URL {
        boardsDirectory.appendingPathComponent("\(boardID.uuidString).json")
    }

    // MARK: - Catalog

    func loadCatalog() throws -> BoardCatalogDTO {
        try decode(BoardCatalogDTO.self, from: catalogURL)
    }

    func saveCatalog(_ catalog: BoardCatalogDTO) throws {
        try encode(catalog, to: catalogURL)
    }

    // MARK: - Per-board snapshots

    func load(boardID: UUID) throws -> BoardSnapshotDTO {
        try decode(BoardSnapshotDTO.self, from: boardURL(boardID))
    }

    func save(boardID: UUID, _ snapshot: BoardSnapshotDTO) throws {
        try FileManager.default.createDirectory(at: boardsDirectory, withIntermediateDirectories: true)
        try encode(snapshot, to: boardURL(boardID))
    }

    func delete(boardID: UUID) throws {
        let url = boardURL(boardID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func listBoardSnapshotIDs() throws -> [UUID] {
        // Distinguish "no boards directory yet" (fresh install → empty, not an error) from a real
        // I/O failure: a `try?` here would collapse a permissions / transient fault to `[]`, which
        // recovery reads as "no snapshots" → bootstrap seeds and orphans every surviving board —
        // reintroducing this PR's data-loss bug through a new path. So return `[]` only when the
        // directory genuinely does not exist, and let any other error propagate (matching
        // `loadLegacy` / `loadTemplate` / `decode`'s absent-vs-failed discipline above).
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: boardsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(
            at: boardsDirectory, includingPropertiesForKeys: nil)
        // Sort so the rebuilt catalog's board order is deterministic (enumeration order is unspecified).
        return entries
            .filter { $0.pathExtension == "json" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.uuidString < $1.uuidString }
    }

    // MARK: - Legacy migration source

    func loadLegacy() throws -> BoardSnapshotDTO? {
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
        return try decode(BoardSnapshotDTO.self, from: legacyURL)
    }

    // MARK: - Default template

    func loadTemplate() throws -> BoardTemplateDTO? {
        guard FileManager.default.fileExists(atPath: templateURL.path) else { return nil }
        return try decode(BoardTemplateDTO.self, from: templateURL)
    }

    func saveTemplate(_ template: BoardTemplateDTO) throws {
        try encode(template, to: templateURL)
    }

    // MARK: - Shared JSON I/O

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OperationError.loadFailed
        }
        let data = try Data(contentsOf: url)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            // Capture which file (and which key/type) won't decode before collapsing to the
            // detail-less `fileCorrupted` — past this point the Repository's recovery log can only
            // say "a snapshot won't decode", never which one or why. Filename is operational
            // (public); the `DecodingError` may quote persisted content, so it stays redacted.
            diagnostics.emit("board store: JSON decode failed for \(url.lastPathComponent)",
                             privateDetail: "\(error)", level: .error)
            throw OperationError.fileCorrupted
        }
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        // Record our own write (its exact post-write mtime) so the watcher reads the resulting
        // directory-change event as self, not external, and skips the reload echo (ticket 5BC2FF20).
        writeLedger.recordSelfWrite(url)
    }
}
