import XCTest
@testable import KanvasCore

/// `BoardStoreWriteLedger` self-echo suppression (ticket 5BC2FF20): a file this process wrote reads
/// as self (no reload), a file another process changed reads as external (reload), and a consumed
/// change is not re-reported so a later self-write event stays a no-op. mtimes are set explicitly so
/// the assertions never depend on filesystem timestamp resolution.
final class BoardStoreWriteLedgerTests: XCTestCase {

    private var directory: URL!
    private var ledger: BoardStoreWriteLedger!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KanvasLedgerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ledger = BoardStoreWriteLedger()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        ledger = nil
        directory = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func writeFile(_ name: String, modifiedAt date: Date) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    private func touch(_ url: URL, modifiedAt date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    // MARK: - consumeExternalChange

    func testConsumeExternalChange_afterRecordingSelfWrite_reportsNoChange() throws {
        let url = try writeFile("catalog.json", modifiedAt: Date(timeIntervalSince1970: 1_000))
        ledger.recordSelfWrite(url)

        XCTAssertFalse(ledger.consumeExternalChange(in: [url]))
    }

    func testConsumeExternalChange_whenFileChangedExternally_reportsChange() throws {
        let url = try writeFile("catalog.json", modifiedAt: Date(timeIntervalSince1970: 1_000))
        ledger.recordSelfWrite(url)
        // Another process rewrites the file — its mtime advances past our recorded write.
        try touch(url, modifiedAt: Date(timeIntervalSince1970: 2_000))

        XCTAssertTrue(ledger.consumeExternalChange(in: [url]))
    }

    func testConsumeExternalChange_neverSeenPresentFile_reportsChange() throws {
        let url = try writeFile("boards.json", modifiedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertTrue(ledger.consumeExternalChange(in: [url]))
    }

    func testConsumeExternalChange_neverSeenAbsentFile_reportsNoChange() {
        let url = directory.appendingPathComponent("missing.json")

        XCTAssertFalse(ledger.consumeExternalChange(in: [url]))
    }

    func testConsumeExternalChange_afterConsumingExternalChange_secondCallReportsNoChange() throws {
        let url = try writeFile("catalog.json", modifiedAt: Date(timeIntervalSince1970: 1_000))
        ledger.recordSelfWrite(url)
        try touch(url, modifiedAt: Date(timeIntervalSince1970: 2_000))

        XCTAssertTrue(ledger.consumeExternalChange(in: [url]))
        // The change was consumed: with no further on-disk change, a later event must not re-report it
        // (otherwise a subsequent self-write event would spuriously trigger a reload).
        XCTAssertFalse(ledger.consumeExternalChange(in: [url]))
    }

    func testConsumeExternalChange_oneExternalAmongSelfWrites_reportsChange() throws {
        let catalog = try writeFile("catalog.json", modifiedAt: Date(timeIntervalSince1970: 1_000))
        let board = try writeFile("board.json", modifiedAt: Date(timeIntervalSince1970: 1_000))
        ledger.recordSelfWrite(catalog)
        ledger.recordSelfWrite(board)
        // Only the board is changed externally; the catalog is untouched.
        try touch(board, modifiedAt: Date(timeIntervalSince1970: 3_000))

        XCTAssertTrue(ledger.consumeExternalChange(in: [catalog, board]))
    }

    // MARK: - seed

    func testSeed_establishesCurrentState_soUnchangedReportsNoChange() throws {
        let url = try writeFile("catalog.json", modifiedAt: Date(timeIntervalSince1970: 1_000))
        // Simulates the watcher seeding at startup over a store the app just loaded but never wrote.
        ledger.seed([url])

        XCTAssertFalse(ledger.consumeExternalChange(in: [url]))
    }

    func testSeed_thenExternalChange_reportsChange() throws {
        let url = try writeFile("catalog.json", modifiedAt: Date(timeIntervalSince1970: 1_000))
        ledger.seed([url])
        try touch(url, modifiedAt: Date(timeIntervalSince1970: 2_000))

        XCTAssertTrue(ledger.consumeExternalChange(in: [url]))
    }
}
