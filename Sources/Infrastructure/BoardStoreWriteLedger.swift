import Foundation
import Synchronization

/// Records the on-disk modification time of every file **this process** writes to the board store,
/// so `BoardStoreWatcher` can tell the app's own atomic saves apart from an external write (the
/// `KanvasMCP` server editing the same store) and **skip the self-echo reload**.
///
/// Why this exists: `Data.write(.atomic)` mutates the enclosing directory, so the watcher's
/// `DispatchSource` fires on the app's *own* saves just as it does on the MCP server's. Each such
/// echo ran `BoardViewModel.load()`, which re-reads the whole store from disk — several redundant
/// full-board decodes per single edit (ticket 5BC2FF20). This ledger lets the watcher suppress the
/// echo: it fires `onChange` only when a watched file's on-disk mtime no longer matches what *we*
/// last wrote — i.e. another process changed it.
///
/// **Per-process by design.** Each process records only its own writes, so a file whose on-disk
/// mtime diverges from our last recorded write must have been changed by someone else. The MCP
/// server runs no watcher, so only the app consults this. `Mutex` keeps the type `Sendable` without
/// `@unchecked` — it is touched from the store's blocking-I/O queue (`recordSelfWrite`) and the
/// watcher's private queue (`sync` / `consumeExternalChange`).
final class BoardStoreWriteLedger: Sendable {
    /// File path → the mtime as of the last time this process synced its view of that file (wrote it,
    /// seeded at watch start, or consumed a watcher event). A `nil` value means "absent on disk".
    private let mtimes: Mutex<[String: Date?]> = Mutex([:])

    /// Record that we just wrote `url`, reading back its **actual** on-disk mtime so the comparison
    /// in `consumeExternalChange` is exact (the OS sets the mtime at write time; a wall-clock `Date()`
    /// we captured separately could differ). Called from the store's write choke point.
    func recordSelfWrite(_ url: URL) {
        let mtime = Self.modificationDate(of: url)
        mtimes.withLock { $0[url.path] = mtime }
    }

    /// Establish our recorded view as the current on-disk mtimes of `urls` **without** reporting a
    /// change. Called once when watching starts so the app begins in sync with disk and only a
    /// genuine *later* external write is reported.
    func seed(_ urls: [URL]) {
        mtimes.withLock { recorded in
            for url in urls { recorded[url.path] = Self.modificationDate(of: url) }
        }
    }

    /// True iff any of `urls` differs from our recorded view — i.e. another process wrote it.
    /// **Consumes** the change as a side effect: it rebuilds the recorded view as the current on-disk
    /// state of exactly `urls`, so (a) a later self-write event does not re-report an already-seen
    /// external change — the watcher monitors directories, not individual files, so each fire must
    /// re-check the whole set against our last-known state — and (b) entries for paths no longer in
    /// the watched set (a deleted board, or a recorded `template.json` write the watcher never
    /// queries) are pruned, so the map can't grow unbounded.
    func consumeExternalChange(in urls: [URL]) -> Bool {
        mtimes.withLock { recorded in
            var external = false
            var next: [String: Date?] = [:]
            for url in urls {
                let mtime = Self.modificationDate(of: url)
                // `recorded[url.path]` is `Date??`: outer nil = never seen, inner nil = seen-absent.
                // A never-seen file (outer nil) reads as a change; coalesce both nils to compare the
                // inner `Date?` so a seen-absent file that is still absent is *not* a change.
                if (recorded[url.path] ?? nil) != mtime { external = true }
                next[url.path] = mtime
            }
            recorded = next
            return external
        }
    }

    /// `try?` conflates "absent" with "stat failed" — unlike `JSONBoardStore`, which distinguishes
    /// them — but the failure mode here is benign: a present file we fail to stat reads as `nil`,
    /// which differs from any recorded `Date` and so triggers an *extra* reload (a false positive),
    /// never a *missed* external change (a false negative). The latter would be the dangerous one.
    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
}
