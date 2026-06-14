import XCTest
@testable import KanvasCore

/// `MarkdownJournalStore` — the file-backed durable autosave journal (ticket 44C9D3C2). Pins the
/// save/loadAll/delete round-trip, per-card overwrite (coalescing), the absent-directory case, the
/// malformed-file skip, and double-delete tolerance. Round-trips through a real temp directory so
/// the JSON encode/decode + atomic write are exercised for real. Also pins that a skipped corrupt
/// entry is logged via the diagnostics sink, not dropped silently (ticket 7DA7C85F).
final class MarkdownJournalStoreTests: XCTestCase {

    private var directory: URL!
    private var diagnostics: SpyDiagnosticsSink!
    private var store: MarkdownJournalStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanvas-md-journal-tests-\(UUID().uuidString)", isDirectory: true)
        diagnostics = SpyDiagnosticsSink()
        store = MarkdownJournalStore(directory: directory, diagnostics: diagnostics)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        diagnostics = nil
        directory = nil
        try super.tearDownWithError()
    }

    private func entry(_ cardID: UUID, _ content: String) -> MarkdownJournalEntryDTO {
        MarkdownJournalEntryDTO(cardID: cardID, content: content, enqueuedAt: Date(timeIntervalSince1970: 1_000))
    }

    func testLoadAll_absentDirectory_returnsEmpty() async throws {
        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 0)
    }

    func testSaveThenLoadAll_roundTrips() async throws {
        let cardID = UUID()
        try await store.save(entry(cardID, "hello"))

        let loaded = try await store.loadAll()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.cardID, cardID)
        XCTAssertEqual(loaded.first?.content, "hello")
    }

    func testSave_sameCardTwice_overwrites() async throws {
        let cardID = UUID()
        try await store.save(entry(cardID, "first"))
        try await store.save(entry(cardID, "second"))

        let loaded = try await store.loadAll()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "second")
    }

    func testLoadAll_twoCards_returnsBoth() async throws {
        try await store.save(entry(UUID(), "a"))
        try await store.save(entry(UUID(), "b"))

        let loaded = try await store.loadAll()
        XCTAssertEqual(Set(loaded.map(\.content)), ["a", "b"])
    }

    func testDelete_removesEntry() async throws {
        let cardID = UUID()
        try await store.save(entry(cardID, "x"))
        try await store.delete(cardID: cardID)

        let loaded = try await store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDelete_absentEntry_logsNothing() async throws {
        // The absent-file path is the intended outcome of a clear, not a failure — it must not emit
        // the misleading "stale edit may re-apply" log. (The same `fileExists`-guarded path also
        // catches the cross-process race where another writer removes the entry mid-clear.)
        try await store.delete(cardID: UUID())

        XCTAssertTrue(diagnostics.messages.isEmpty, "an absent-entry clear must emit no diagnostics")
    }

    func testDelete_absentEntry_isNoOp() async throws {
        // A no-op delete must not throw — exercising the absent-file branch (the test fails if it does).
        try await store.delete(cardID: UUID())
    }

    func testLoadAll_skipsMalformedFile() async throws {
        let good = UUID()
        try await store.save(entry(good, "good"))
        // Drop a non-JSON file into the journal directory — it must be skipped, not fail the read.
        let junk = directory.appendingPathComponent("markdown-journal/\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: junk)

        let loaded = try await store.loadAll()

        XCTAssertEqual(loaded.map(\.cardID), [good])
    }

    func testLoadAll_skippedMalformedFile_isLogged() async throws {
        // A corrupt entry must be logged via the sink, never dropped silently — otherwise a stranded
        // unsaved edit is invisibly re-skipped on every launch (ticket 7DA7C85F).
        try await store.save(entry(UUID(), "good"))
        let junkName = "\(UUID().uuidString).json"
        let junk = directory.appendingPathComponent("markdown-journal/\(junkName)")
        try Data("not json".utf8).write(to: junk)

        _ = try await store.loadAll()

        let logged = diagnostics.messages(at: .error)
        XCTAssertTrue(logged.contains { $0.contains("won't decode") && $0.contains(junkName) },
                      "expected a logged skip naming the corrupt file, got \(logged)")
    }

    func testLoadAll_skippedMalformedFile_stillRecoversHealthyEntriesAndLogs() async throws {
        // Pins the full "skip-but-don't-block + observe" contract in one place: a corrupt entry must
        // be skipped *and logged*, while every healthy card is still recovered (ticket 7DA7C85F).
        let good = UUID()
        try await store.save(entry(good, "good"))
        let junkName = "\(UUID().uuidString).json"
        try Data("not json".utf8).write(to: directory.appendingPathComponent("markdown-journal/\(junkName)"))

        let loaded = try await store.loadAll()

        XCTAssertEqual(loaded.map(\.cardID), [good],
                       "the healthy entry must survive a sibling corrupt file")
        XCTAssertTrue(diagnostics.messages(at: .error).contains { $0.contains("won't decode") },
                      "the skip must be logged, not silent")
    }

    func testLoadAll_allEntriesValid_logsNothing() async throws {
        // The healthy path must stay quiet — no skip log when every entry decodes.
        try await store.save(entry(UUID(), "a"))
        try await store.save(entry(UUID(), "b"))

        _ = try await store.loadAll()

        XCTAssertTrue(diagnostics.messages.isEmpty, "a clean load must emit no diagnostics")
    }

    func testSave_failure_isLogged() async throws {
        // Point the store at a path it cannot create a directory under (a *file* sits where the
        // store root's parent must be a directory), forcing the write to throw — the failure must be
        // both rethrown and logged (ticket 7DA7C85F).
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanvas-md-journal-blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let wedged = MarkdownJournalStore(
            directory: blocker.appendingPathComponent("under-a-file", isDirectory: true),
            diagnostics: diagnostics
        )

        do {
            try await wedged.save(entry(UUID(), "x"))
            XCTFail("expected save to throw when its directory cannot be created")
        } catch {
            XCTAssertTrue(diagnostics.messages(at: .error).contains { $0.contains("write-ahead save failed") },
                          "expected a logged write-ahead save failure, got \(diagnostics.messages(at: .error))")
        }
    }
}
