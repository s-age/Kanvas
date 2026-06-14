import Foundation
import os
import Synchronization
#if canImport(Darwin)
import Darwin
#endif

/// Process-wide advisory lock that serializes the board store's read-modify-write across
/// **separate processes** — the app and the `KanvasMCP` server share one Application Support
/// directory, so without it the last writer's whole-snapshot save silently clobbers the other's.
///
/// Backed by `flock(2)` on a single long-lived descriptor to a sentinel `.kanvas.lock` file.
/// An `flock` is owned by the *open file description*, so all callers in this process share one
/// lock against other processes — but that same sharing means a second in-process caller's
/// `LOCK_EX` succeeds immediately and the first `LOCK_UN` would release the lock while the other
/// is still inside its critical section. The in-process `Mutex` below closes that hole: callers
/// are serialized first, so each `flock` acquire/release pairs with exactly one critical section.
///
/// **Not reentrant**: a nested `withExclusiveLock` from inside `body` deadlocks on the `Mutex`.
/// No current caller nests (the single call site is `JSONBoardStore.withExclusiveAccess`).
final class FileLock: Sendable {
    private static let logger = Logger(subsystem: "com.kanvas.app", category: "filelock")

    private let descriptor: Int32
    /// Serializes in-process callers so the cross-process `flock` is held for exactly one
    /// critical section at a time (see the type comment).
    ///
    /// Note: the board store now also funnels every caller through a single serial `BlockingIOQueue`
    /// (so the flock + I/O runs off the cooperative pool), which already guarantees one in-process
    /// caller at a time — making this `Mutex` redundant *for the board store's path*. It is kept
    /// because it is `FileLock`'s own invariant, not the store's: `FileLock` must pair each
    /// acquire/release with exactly one critical section regardless of how callers are scheduled, so
    /// the guard stays load-bearing for any future (non-serial-queue) caller.
    private let inProcess = Mutex<Void>(())

    init(path: URL) {
        // O_CLOEXEC: a forked/exec'd child must not inherit the lock fd. `deinit` closes the
        // descriptor; in production that fires only at process exit (the store holds one long-lived
        // `FileLock`), but it keeps a test suite that builds many containers from leaking an fd each.
        descriptor = open(path.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        if descriptor < 0 {
            // Degraded mode: every withExclusiveLock call will run unlocked. Say so once —
            // a silent degradation here would surface only as unexplained lost writes.
            Self.logger.error(
                """
                Failed to open lock file \(path.path, privacy: .public) (errno \(errno)); \
                proceeding without cross-process locking
                """
            )
        }
    }

    deinit {
        // Release the lock fd. Production fires this only at process exit (one long-lived instance),
        // but without it every test-built container leaks the `open`ed descriptor for the run.
        if descriptor >= 0 { close(descriptor) }
    }

    /// Runs `body` while holding an exclusive (`LOCK_EX`) lock, releasing it on return or throw.
    /// If the lock file could not be opened, runs `body` unlocked — best-effort degradation rather
    /// than blocking all persistence on a lock we could not acquire (logged once in `init`).
    ///
    /// `flock` is a blocking syscall: while another process holds the lock, this call parks its
    /// thread (a cooperative-pool thread when reached from an async use case).
    func withExclusiveLock<T>(_ body: () throws -> T) rethrows -> T {
        try inProcess.withLock { _ in
            guard descriptor >= 0 else { return try body() }
            // Retry on EINTR — a signal must not silently skip the lock acquisition.
            var acquired = flock(descriptor, LOCK_EX)
            while acquired == -1 && errno == EINTR { acquired = flock(descriptor, LOCK_EX) }
            if acquired == -1 {
                // Non-EINTR failure (e.g. ENOLCK) — effectively unreachable for an flock on a
                // local file, but if it ever fires, say so rather than degrade silently.
                Self.logger.error("flock(LOCK_EX) failed (errno \(errno)); running this section unlocked")
            }
            defer { flock(descriptor, LOCK_UN) }
            return try body()
        }
    }
}
