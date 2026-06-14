import Foundation

/// File-backed durable journal for pending Markdown autosave edits (ticket 44C9D3C2). Each card's
/// latest unsaved text lives at `markdown-journal/<cardID>.json` under the injected base directory
/// (the same Application Support root the board store uses) — out-of-band from the board snapshot,
/// on a separate substrate that does **not** go through the board's `flock`/undo. One file per card
/// makes the journal naturally coalescing: re-saving overwrites the card's file with the latest
/// text.
///
/// All methods are storage primitives; no domain decisions live here (those belong to
/// `MarkdownJournalRepository`).
final class MarkdownJournalStore: MarkdownJournalStoreProtocol, Sendable {
    private let directory: URL
    /// Runs the blocking file I/O off the cooperative pool (see `MarkdownJournalStoreProtocol`).
    private let ioQueue: BlockingIOQueue
    /// Surfaces every silent degradation of this best-effort durability layer (a corrupt entry
    /// skipped on load, a write-ahead save that failed, a clear that failed) so a stranded unsaved
    /// edit is never invisibly re-skipped on each launch (ticket 7DA7C85F). The store writes to the
    /// sink directly — the same `DiagnosticsSinkProtocol` the Repository observes — never a second
    /// `os.Logger` (arch-infrastructure → "Persisted-blob decode: corrupt vs absent").
    private let diagnostics: any DiagnosticsSinkProtocol

    init(directory: URL, diagnostics: any DiagnosticsSinkProtocol) {
        self.directory = directory
        self.diagnostics = diagnostics
        // `.utility`: the autosave journal is best-effort durability, not interactive work.
        ioQueue = BlockingIOQueue(label: "com.kanvas.markdownjournalstore.io", qos: .utility)
    }

    private var journalDirectory: URL { directory.appendingPathComponent("markdown-journal", isDirectory: true) }

    private func entryURL(_ cardID: UUID) -> URL {
        journalDirectory.appendingPathComponent("\(cardID.uuidString).json")
    }

    func save(_ entry: MarkdownJournalEntryDTO) async throws {
        let journalDirectory = self.journalDirectory
        let url = entryURL(entry.cardID)
        let diagnostics = self.diagnostics
        try await ioQueue.run {
            do {
                try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(entry)
                try data.write(to: url, options: .atomic)
            } catch {
                // The write-ahead journal is best-effort (the caller swallows this throw so a
                // journal failure never blocks the real write), but a failure means this card's
                // unsaved edit is *not* durably journaled — the durability layer silently going
                // absent under a permanent fault (permissions, disk full) is exactly the silent
                // degradation forbidden here. Log via the sink before rethrowing; the caller still
                // decides (best-effort) what to do. The filename names the card (operational,
                // public); the error may quote a path, so it stays redacted.
                diagnostics.emit(
                    "markdown journal: write-ahead save failed; edit not durably journaled (\(url.lastPathComponent))",
                    privateDetail: "\(error)", level: .error
                )
                throw error
            }
        }
    }

    func loadAll() async throws -> [MarkdownJournalEntryDTO] {
        let journalDirectory = self.journalDirectory
        let diagnostics = self.diagnostics
        return try await ioQueue.run {
            // A fresh install (or a session that never journaled) has no journal directory; that is
            // absence, not an error — report nothing to restore.
            guard FileManager.default.fileExists(atPath: journalDirectory.path) else { return [] }
            let urls: [URL]
            do {
                urls = try FileManager.default.contentsOfDirectory(
                    at: journalDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            } catch {
                // The directory exists but won't enumerate (permissions, a transient I/O fault):
                // the *whole* restore is aborted this launch, so it must be observable — a silent
                // skip here is the "restore全体中止" failure mode. Log, then rethrow so the caller
                // (`restorePendingMarkdownSaves`) can leave the once-per-launch guard unset and
                // retry next session, rather than recording an empty journal as the truth.
                diagnostics.emit(
                    "markdown journal: could not enumerate the journal directory; restore is aborted this launch",
                    privateDetail: "\(error)", level: .error
                )
                throw error
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var entries: [MarkdownJournalEntryDTO] = []
            for url in urls where url.pathExtension == "json" {
                // Skip a malformed or unreadable journal file rather than failing the whole restore
                // — one corrupt entry must not block recovering every other card's unsaved edit. The
                // file is left in place (not deleted) so a future fix could still recover it
                // manually. But never *silently*: log each skip via the injected sink, or a stranded
                // unsaved edit is invisibly re-skipped on every launch (arch-infrastructure →
                // "Persisted-blob decode: corrupt vs absent"; mirrors `JSONBoardStore.decode`). The
                // filename names the card (operational, public); the error may quote persisted
                // content, so it stays redacted.
                //
                // Deliberately *no* per-(process, record) dedup like `BoardRepository`'s
                // `loggedRecoveries`: that suppression exists because the whole-blob board store
                // rewrites the snapshot, so a read-time recovery is a latent write worth logging
                // once. The journal file is never rewritten here, so there is no latent write-back —
                // and re-surfacing a still-stranded edit on each launch (restore is guarded once per
                // session, so it is once per launch) is desirable, not noise.
                do {
                    let data = try Data(contentsOf: url)
                    entries.append(try decoder.decode(MarkdownJournalEntryDTO.self, from: data))
                } catch {
                    diagnostics.emit(
                        "markdown journal: skipped an entry that won't decode (\(url.lastPathComponent))",
                        privateDetail: "\(error)", level: .error
                    )
                }
            }
            return entries
        }
    }

    func delete(cardID: UUID) async throws {
        let url = entryURL(cardID)
        let diagnostics = self.diagnostics
        try await ioQueue.run {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                // A concurrent remover (the MCP server, or another app path) can delete this same
                // entry between the existence check above and `removeItem` here — and the entry
                // being gone is exactly the outcome a clear wants, not a failure. Re-check and treat
                // absence as success, so the genuine-failure log below never fires for the
                // cross-process race it was meant to surface (a "stale edit may re-apply" warning
                // would be a lie when no file remains to re-apply).
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                // A clear that genuinely failed leaves a stale journal entry that a later launch
                // re-applies — and with another writer in play (an MCP `markdown_set` between this
                // save and that launch) re-applying it resurrects superseded text over the newer
                // write. Best-effort (the caller swallows this throw), but the stale-entry risk must
                // not be silent. Log before rethrowing. Filename public; error redacted.
                diagnostics.emit(
                    "markdown journal: clear failed; a stale edit may re-apply next launch (\(url.lastPathComponent))",
                    privateDetail: "\(error)", level: .error
                )
                throw error
            }
        }
    }
}
