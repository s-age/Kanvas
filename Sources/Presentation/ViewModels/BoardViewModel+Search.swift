import Foundation

// Live card search (ticket 59B10FBA), split into its own file so `BoardViewModel.swift` stays within
// the file-length budget. Debounces `searchText` edits (~200ms) into one `SearchCardsUseCase` call,
// cancelling the prior in-flight search so rapid typing never fans out a call per keystroke. A blank
// query clears the filter immediately, with no use-case round-trip. The result is published through
// `applyMatchedCardIDs` (the main file owns the `private(set) matchedCardIDs`).

extension BoardViewModel {

    /// Debounce interval between the last keystroke and the search call.
    private static let searchDebounce: Duration = .milliseconds(200)

    /// Whether a card is visible under the current filter. `nil` filter ⇒ every card shows; otherwise
    /// only ids in the matched set. The kanban view filters each column's cards through this.
    func isCardVisible(_ id: UUID) -> Bool {
        guard let matchedCardIDs else { return true }
        return matchedCardIDs.contains(id)
    }

    /// Called from `searchText.didSet`. A blank query short-circuits to "no filter" with no delay; a
    /// non-blank query debounces, then runs the search and publishes the result.
    func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            applyMatchedCardIDs(nil)
            searchTask = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }
            await self?.runSearch(query: query)
        }
    }

    /// Clears the search field and any active filter — used on a board switch (search is active-board
    /// scoped). Cancels any in-flight search so it can't land on the new board.
    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        // Assigning `searchText` re-enters `scheduleSearch` via `didSet`, which — for a blank query —
        // clears the filter (`applyMatchedCardIDs(nil)`). No explicit clear is needed here; a trailing
        // `applyMatchedCardIDs(nil)` would re-apply the same nil filter a second time (PR #123 r1-2).
        searchText = ""
    }

    /// Adopts the match the combined board-view-state read already computed over the **same** decoded
    /// state (PR #123 r2-1), so a live refresh (store-watcher fire / in-app or MCP card edit) keeps
    /// `matchedCardIDs` fresh — a newly-matching card no longer stays hidden, a no-longer-matching one
    /// no longer stays shown — without the second store read the former `refreshSearchIfActive` →
    /// `SearchCards` round-trip paid. Called from `applyBoardViewState` (the single board-publish
    /// funnel).
    ///
    /// **Staleness guard**: the refresh is async, so the user may have typed on between `load()`
    /// capturing `searchText` and this landing. `matchedQuery` is the trimmed text the result was
    /// computed for; adopt it only while it still equals the live field — otherwise the pending
    /// debounced search (or the next refresh) owns the current query, and a stale set must not
    /// overwrite it. A blank `matchedQuery` is the no-filter sentinel: adopt `nil` only while the
    /// field is still blank, for the same reason.
    func adoptRefreshedMatch(_ matched: Set<UUID>?, for matchedQuery: String) {
        let liveQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard liveQuery == matchedQuery else { return }
        applyMatchedCardIDs(matched)
    }

    private func runSearch(query: String) async {
        do {
            let matched = try await managementUseCases.search.execute(query: query)
            // Stale-result guard: the await may outlive the query it was issued for — the user can
            // type on (even past `searchTask` cancellation, once `execute` is suspended) before this
            // lands. Adopt only while the live field still equals `query`, the exact-equality guard
            // the sibling `adoptRefreshedMatch` uses (PR #123 r3-1); any other field value — blank or
            // a newer non-blank query — is owned by the pending debounced search, not this stale set.
            guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            applyMatchedCardIDs(matched)
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }
}
