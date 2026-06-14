import Foundation

/// File-backed image asset store. Each image's pixels live at `assets/<imageID>.png` under the
/// injected base directory (the same Application Support root the board store uses), so the board
/// JSON only ever references an id — never carries the bytes.
final class FileImageAssetStore: ImageAssetStoreProtocol, Sendable {
    private let directory: URL
    /// `.userInitiated` queue backing the one interactive path, `load(assetID:)` — the canvas draw
    /// path (`CanvasNSView+Images.loadImageIfNeeded` → `viewModel.loadImageData` → here) where the
    /// user stares at a placeholder until it completes, so it must not be deprioritised under CPU
    /// pressure (ticket 84FA9FF2).
    private let interactiveQueue: BlockingIOQueue
    /// `.utility` queue backing every best-effort path — `save` / `delete` / `assetIDs` (orphan-GC
    /// scan): sidecar persistence and enumeration, not interactive work. Split out so a slow GC
    /// sweep can never deprioritise an interactive read.
    ///
    /// The two queues split by **QoS axis** (interactive vs best-effort), not reader vs writer —
    /// they are *not* a reader-writer lock and give no cross-queue ordering. Operations on the
    /// interactive queue are no longer serialised against operations on the best-effort queue. That
    /// is benign here: assets are write-once (`save` then immutable), each write is `.atomic`, and
    /// GC only deletes assets the board no longer references, so a concurrent `load` can never race
    /// a `delete`/overwrite of the asset it is reading.
    private let bestEffortQueue: BlockingIOQueue

    init(directory: URL) {
        self.directory = directory
        interactiveQueue = BlockingIOQueue(label: "com.kanvas.imageassetstore.interactive", qos: .userInitiated)
        bestEffortQueue = BlockingIOQueue(label: "com.kanvas.imageassetstore.besteffort", qos: .utility)
    }

    private var assetsDirectory: URL { directory.appendingPathComponent("assets", isDirectory: true) }

    private func assetURL(_ assetID: UUID) -> URL {
        assetsDirectory.appendingPathComponent("\(assetID.uuidString).png")
    }

    func save(assetID: UUID, data: Data) async throws {
        let directory = assetsDirectory
        let url = assetURL(assetID)
        try await bestEffortQueue.run {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    func load(assetID: UUID) async throws -> Data {
        let url = assetURL(assetID)
        return try await interactiveQueue.run {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw OperationError.loadFailed
            }
            return try Data(contentsOf: url)
        }
    }

    func delete(assetID: UUID) async throws {
        let url = assetURL(assetID)
        try await bestEffortQueue.run {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        }
    }

    func assetIDs(modifiedBefore cutoff: Date) async throws -> Set<UUID> {
        let assetsDirectory = self.assetsDirectory
        return try await bestEffortQueue.run {
            // A fresh install (or a session that never added an image) has no assets directory; that
            // is absence, not an error — report nothing to sweep.
            guard FileManager.default.fileExists(atPath: assetsDirectory.path) else { return [] }
            let urls = try FileManager.default.contentsOfDirectory(
                at: assetsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            var ids: Set<UUID> = []
            for url in urls where url.pathExtension == "png" {
                // Skip anything that is not a `<uuid>.png` or whose mtime is unreadable — only a file
                // we can both identify *and* age may be considered for sweeping.
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let modified = try url.resourceValues(forKeys: [.contentModificationDateKey])
                          .contentModificationDate,
                      modified < cutoff
                else { continue }
                ids.insert(id)
            }
            return ids
        }
    }
}
