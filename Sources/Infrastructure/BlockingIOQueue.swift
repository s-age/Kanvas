import Foundation

/// Runs synchronous, blocking file I/O **off the Swift cooperative thread pool**, on a dedicated
/// serial `DispatchQueue`. The async caller suspends via the continuation — releasing its
/// cooperative-pool thread — instead of parking it on a blocking `flock`/JSON I/O syscall.
///
/// Why this exists: every store operation is reached from a `nonisolated async` use case, so it
/// runs on the cooperative pool. The board store's `flock(LOCK_EX)` (no timeout) and whole-snapshot
/// JSON reads/writes are blocking; parking a pool thread on them — while the in-process `Mutex` is
/// held — can starve every other async task when another process (the MCP server) holds the lock.
/// Offloading the blocking section here keeps the cooperative pool free.
///
/// A `Task.detached` would **not** fix this: detached tasks run on the same global (cooperative)
/// executor, so the blocking work would still occupy a pool thread. A dedicated `DispatchQueue` is
/// a genuinely separate thread, which is the point.
///
/// The queue is **serial** by design: the board store relies on it to keep the `flock` critical
/// section single-threaded, and the image/journal stores are correct (if not maximally parallel)
/// under serial execution too.
///
/// `qos` is the caller's choice because a bare `withCheckedThrowingContinuation { queue.async { … } }`
/// does **not** donate the awaiting context's priority to the GCD block — the queue's own QoS is what
/// the work runs at. The board store backs user-interactive edits (drag a sticky → `mutate` → the
/// awaited `BoardState` repaints the canvas, often awaited from the `@MainActor`), so it asks for
/// `.userInitiated` to avoid a priority inversion under CPU pressure. Other callers pick the QoS
/// that matches their work: `MarkdownJournalStore` is best-effort persistence and uses `.utility`,
/// while `FileImageAssetStore` runs two queues — a `.userInitiated` one for its interactive
/// `load(assetID:)` (the canvas draw path) and a `.utility` one for its best-effort save/delete/GC
/// (ticket 84FA9FF2).
final class BlockingIOQueue: Sendable {
    private let queue: DispatchQueue

    init(label: String, qos: DispatchQoS) {
        // Serial (no `.concurrent` attribute).
        queue = DispatchQueue(label: label, qos: qos)
    }

    /// Runs `work` on the dedicated serial queue and resumes the caller with its result or thrown
    /// error. The caller is suspended (not blocked) for the duration.
    func run<T: Sendable>(_ work: @Sendable @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
