import XCTest
@testable import KanvasCore

/// `FileImageAssetStore.assetIDs(modifiedBefore:)` — the orphan-GC candidate scan. Pins the grace
/// filter (only files older than the cutoff are reported), the absent-directory case, and that
/// non-UUID files are ignored. Round-trips through a real temp directory so the mtime read is real.
final class FileImageAssetStoreTests: XCTestCase {

    private var directory: URL!
    private var store: FileImageAssetStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanvas-asset-store-tests-\(UUID().uuidString)", isDirectory: true)
        store = FileImageAssetStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
        try super.tearDownWithError()
    }

    /// Sets `assetID`'s asset file mtime to `age` seconds in the past (relative to a fixed `now`).
    private func saveAsset(_ assetID: UUID, agedSeconds age: TimeInterval, now: Date) async throws {
        try await store.save(assetID: assetID, data: Data([0x1]))
        let url = directory.appendingPathComponent("assets/\(assetID.uuidString).png")
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path
        )
    }

    func testAssetIDs_absentDirectory_returnsEmpty() async throws {
        let swept = try await store.assetIDs(modifiedBefore: Date())
        XCTAssertEqual(swept, [])
    }

    func testAssetIDs_reportsAssetOlderThanCutoff() async throws {
        let now = Date()
        let old = UUID()
        try await saveAsset(old, agedSeconds: 7200, now: now)

        let swept = try await store.assetIDs(modifiedBefore: now.addingTimeInterval(-3600))

        XCTAssertEqual(swept, [old])
    }

    func testAssetIDs_excludesAssetNewerThanCutoff() async throws {
        let now = Date()
        let fresh = UUID()
        try await saveAsset(fresh, agedSeconds: 60, now: now)

        let swept = try await store.assetIDs(modifiedBefore: now.addingTimeInterval(-3600))

        XCTAssertFalse(swept.contains(fresh))
    }

    func testAssetIDs_ignoresFilesNotNamedByUUID() async throws {
        let now = Date()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        let strayURL = directory.appendingPathComponent("assets/not-a-uuid.png")
        try Data([0x1]).write(to: strayURL)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: strayURL.path
        )

        let swept = try await store.assetIDs(modifiedBefore: now.addingTimeInterval(-3600))
        XCTAssertEqual(swept, [])
    }
}
