import XCTest
@testable import KanvasCore

/// `JSONBoardStore` file I/O over a real temp directory: catalog and per-board snapshots round-trip,
/// absence is reported as `loadFailed`, deletion removes the file, and the legacy file is read only
/// when present.
final class JSONBoardStoreTests: XCTestCase {

    private var directory: URL!
    private var store: JSONBoardStore!
    private var diagnostics: SpyDiagnosticsSink!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KanvasStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        diagnostics = SpyDiagnosticsSink()
        store = JSONBoardStore(directory: directory, writeLedger: BoardStoreWriteLedger(),
                               diagnostics: diagnostics)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
        diagnostics = nil
        try super.tearDownWithError()
    }

    // MARK: - catalog

    func testCatalog_roundTrips() throws {
        let id = UUID()
        let catalog = BoardCatalogDTO(activeBoardID: id, boards: [BoardRefDTO(id: id, title: "A")])

        try store.saveCatalog(catalog)
        let loaded = try store.loadCatalog()

        XCTAssertEqual(loaded.activeBoardID, id)
        XCTAssertEqual(loaded.boards.map(\.title), ["A"])
    }

    func testLoadCatalog_absent_throwsLoadFailed() throws {
        do {
            _ = try store.loadCatalog()
            XCTFail("Expected loadFailed")
        } catch let error as OperationError {
            XCTAssertEqual(error, .loadFailed)
        }
    }

    // MARK: - per-board snapshot

    func testBoardSnapshot_roundTrips() throws {
        let state = BoardState.withDefaultColumns(title: "Board")
        let id = state.board.id

        try store.save(boardID: id, BoardSnapshotMapper.toDTO(state))
        let loaded = try store.load(boardID: id)

        XCTAssertEqual(loaded.board.id, id)
        XCTAssertEqual(loaded.columns.map(\.title), ["To Do", "In Progress", "Done"])
    }

    func testLoad_absentBoard_throwsLoadFailed() throws {
        do {
            _ = try store.load(boardID: UUID())
            XCTFail("Expected loadFailed")
        } catch let error as OperationError {
            XCTAssertEqual(error, .loadFailed)
        }
    }

    func testLoad_corruptSnapshot_throwsFileCorrupted() throws {
        let id = UUID()
        let boardsDirectory = directory.appendingPathComponent("boards", isDirectory: true)
        try FileManager.default.createDirectory(at: boardsDirectory, withIntermediateDirectories: true)
        try Data("{ not valid json".utf8)
            .write(to: boardsDirectory.appendingPathComponent("\(id.uuidString).json"))

        do {
            _ = try store.load(boardID: id)
            XCTFail("Expected fileCorrupted")
        } catch let error as OperationError {
            XCTAssertEqual(error, .fileCorrupted)
        }
    }

    func testLoad_corruptSnapshot_logsDecodeDetailNamingTheFile() throws {
        // The decode detail (which file + which key) is lost once `fileCorrupted` is thrown, so the
        // store must surface it before collapsing — name the file publicly, keep the error redacted.
        let id = UUID()
        let boardsDirectory = directory.appendingPathComponent("boards", isDirectory: true)
        try FileManager.default.createDirectory(at: boardsDirectory, withIntermediateDirectories: true)
        try Data("{ not valid json".utf8)
            .write(to: boardsDirectory.appendingPathComponent("\(id.uuidString).json"))

        _ = try? store.load(boardID: id)

        let errors = diagnostics.messages(at: .error)
        XCTAssertTrue(errors.contains { $0.contains("\(id.uuidString).json") },
                      "Expected a decode-failure log naming the snapshot file; got \(errors)")
        XCTAssertFalse(diagnostics.messages.compactMap(\.privateDetail).isEmpty,
                       "Expected the DecodingError carried as redacted privateDetail")
    }

    func testDelete_removesTheSnapshotFile() throws {
        let state = BoardState.withDefaultColumns(title: "Board")
        let id = state.board.id
        try store.save(boardID: id, BoardSnapshotMapper.toDTO(state))

        try store.delete(boardID: id)

        do {
            _ = try store.load(boardID: id)
            XCTFail("Expected loadFailed after delete")
        } catch let error as OperationError {
            XCTAssertEqual(error, .loadFailed)
        }
    }

    // MARK: - legacy

    func testLoadLegacy_absent_returnsNil() throws {
        XCTAssertNil(try store.loadLegacy())
    }

    func testLoadLegacy_present_decodesLegacyFile() throws {
        // Write a legacy `board.json` directly into the directory, mirroring a pre-multi-board app.
        let legacy = BoardState.withDefaultColumns(title: "Legacy")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(BoardSnapshotMapper.toDTO(legacy))
        try data.write(to: directory.appendingPathComponent("board.json"), options: .atomic)

        let loaded = try store.loadLegacy()

        XCTAssertEqual(loaded?.board.title, "Legacy")
    }
}
