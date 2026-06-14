import Foundation
import Synchronization
#if canImport(Darwin)
import Darwin
#endif

/// Watches the board store directory for **external** writes (the `KanvasMCP` server editing the
/// same JSON the app has open) and fires a debounced callback so Presentation can reload. Pure
/// mechanism — it knows nothing about boards; it just reports "the store changed".
///
/// `Data.write(.atomic)` replaces a file by writing a temp then renaming over the target, which
/// mutates the *enclosing directory*. So watching the two parent directories — the root (for
/// `catalog.json`) and `boards/` (for every `<id>.json` snapshot) — catches every save. Backed by
/// `DispatchSource` VFS monitors; the non-`Sendable` sources live behind a `Mutex`, which is what
/// keeps the watcher `Sendable` without `@unchecked`.
final class BoardStoreWatcher: BoardStoreWatcherProtocol, Sendable {
    /// `[0]` is the store root (holds `catalog.json`), `[1]` is its `boards/` subdirectory — the two
    /// directories whose entries change on an atomic save. `storeFiles()` derives the watched file
    /// set from these, so the root is not stored separately.
    private let watchedDirectories: [URL]
    private let queue = DispatchQueue(label: "com.kanvas.boardstore.watcher")
    private let sources: Mutex<[any DispatchSourceFileSystemObject]> = Mutex([])
    /// Monotonic event generation used to debounce: each event bumps it and schedules a delayed
    /// fire that runs only if it is still the latest. A plain `Int` (vs a stored `DispatchWorkItem`)
    /// keeps the box `Sendable`-clean — a non-`Sendable` work item cannot cross the `Mutex` inout.
    private let generation: Mutex<Int> = Mutex(0)
    private let debounceInterval: TimeInterval
    /// Shared with `JSONBoardStore`: lets a debounced fire tell the app's own atomic saves apart from
    /// an external (MCP) write by mtime, so a self-echo skips the reload (ticket 5BC2FF20).
    private let writeLedger: BoardStoreWriteLedger
    /// Reports a setup failure (a watched directory that won't create or whose monitor won't open) —
    /// either silently disables live refresh, making "MCP edits don't appear" indistinguishable from
    /// "this watcher never started". See `start` / `makeSource`.
    private let diagnostics: any DiagnosticsSinkProtocol

    init(directory: URL, writeLedger: BoardStoreWriteLedger,
         diagnostics: any DiagnosticsSinkProtocol, debounceInterval: TimeInterval = 0.2) {
        self.writeLedger = writeLedger
        self.diagnostics = diagnostics
        self.debounceInterval = debounceInterval
        watchedDirectories = [
            directory,
            directory.appendingPathComponent("boards", isDirectory: true),
        ]
    }

    /// Begins watching. `onChange` runs on a private queue, debounced, after any watched directory
    /// changes — **unless** the change is the app's own save (self-echo), which is filtered out by
    /// the write ledger. Calling again replaces the source set (cancelling the previous monitors).
    func start(onChange: @escaping @Sendable () -> Void) {
        // `boards/` may not exist until the first save — create it so its monitor can open.
        do {
            try FileManager.default.createDirectory(
                at: watchedDirectories[1], withIntermediateDirectories: true
            )
        } catch {
            // The `boards/` monitor below then can't open, so external (MCP) snapshot edits won't
            // live-refresh the app — log it instead of letting that look like "MCP edits ignored".
            diagnostics.emit(
                "board store watcher: could not create the boards/ directory; "
                    + "live refresh of board snapshots is disabled",
                privateDetail: "\(error)", level: .error
            )
        }
        // Seed the ledger to the current on-disk state so only a genuine *later* external write fires
        // — the app's startup load already established this process's view of the store.
        writeLedger.seed(storeFiles())
        sources.withLock { existing in
            existing.forEach { $0.cancel() }
            existing = watchedDirectories.compactMap { url in
                makeSource(for: url, onChange: onChange)
            }
        }
    }

    func stop() {
        sources.withLock { existing in
            existing.forEach { $0.cancel() }
            existing = []
        }
        // Bump the generation so any already-scheduled fire sees itself as stale and no-ops.
        generation.withLock { $0 += 1 }
    }

    private func makeSource(
        for url: URL, onChange: @escaping @Sendable () -> Void
    ) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            let err = errno
            // No VFS monitor for this directory → its on-disk changes never trigger a live refresh.
            // Say so (the errno separates a permissions fault from a still-missing path); the full
            // path may include the user's home, so keep it redacted.
            diagnostics.emit(
                "board store watcher: could not open \(url.lastPathComponent) for monitoring "
                    + "(errno \(err)); live refresh is disabled for it",
                privateDetail: url.path, level: .error
            )
            return nil
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleFire(onChange) }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func scheduleFire(_ onChange: @escaping @Sendable () -> Void) {
        let mine = generation.withLock { current -> Int in
            current += 1
            return current
        }
        queue.asyncAfter(deadline: .now() + debounceInterval) { [weak self] in
            guard let self, self.generation.withLock({ $0 == mine }) else { return }
            // Suppress the self-echo: fire only when a watched file's on-disk mtime no longer matches
            // what this process last wrote (an external/MCP edit). Our own atomic saves are consumed
            // here as no-ops, so a single edit no longer triggers a full-board reload (ticket 5BC2FF20).
            guard self.writeLedger.consumeExternalChange(in: self.storeFiles()) else { return }
            onChange()
        }
    }

    /// The store files whose content the watcher mirrors: the catalog index plus every board
    /// snapshot. (Template/journal/asset files are not watched for live refresh.) Enumerated fresh on
    /// each call so a board added by the other process is included.
    private func storeFiles() -> [URL] {
        var files = [watchedDirectories[0].appendingPathComponent("catalog.json")]
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: watchedDirectories[1], includingPropertiesForKeys: nil) {
            files += entries.filter { $0.pathExtension == "json" }
        }
        return files
    }
}
