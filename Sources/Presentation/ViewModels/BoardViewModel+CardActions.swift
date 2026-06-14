import Foundation

// Card CRUD, split into its own file so `BoardViewModel.swift` stays within the file-length budget.

extension BoardViewModel {

    /// Adds a card and returns the new card's ID so the caller can immediately
    /// enter rename mode on it.
    @discardableResult
    func addCard(title: String, columnID: UUID) async -> UUID? {
        do {
            let response = try await kanbanUseCases.addCard.execute(AddCardRequest(title: title, columnID: columnID))
            applyBoard(response.board)
            return response.newCardID
        } catch {
            self.error = error
            return nil
        }
    }

    /// Returns whether the edit was persisted, so a caller tracking a dirty baseline only
    /// clears it on success and survives a failed write. Used by the one-shot metadata edits
    /// (title / prURL / schedule / Kanban rename); the Markdown autosave goes through
    /// `enqueueMarkdownSave` instead so its writes are serialized and retried.
    @discardableResult
    func editCard(_ request: EditCardRequest) async -> Bool {
        do {
            try await applyEditedCard(request)
            return true
        } catch {
            self.error = error
            return false
        }
    }

    /// Hand a Markdown edit to the serialized autosave channel. Synchronous — the editor can
    /// call it from `onDisappear` and the write still completes (and retries on failure)
    /// because the queue lives on the ViewModel, not the view. Coalesces to the latest text
    /// per card and serializes writes, closing the fire-and-forget gaps (ticket B817F0D2).
    func enqueueMarkdownSave(cardID: UUID, content: String) {
        markdownAutosave.enqueue(cardID: cardID, content: content)
    }

    /// Whether the autosave channel still owes the disk an edit for this card — the editor's
    /// authoritative "buffer dirty?" signal, so an external `markdown_set` rewrite never
    /// adopts over a not-yet-persisted local edit.
    func hasPendingMarkdownSave(_ cardID: UUID) -> Bool {
        markdownAutosave.hasPending(cardID)
    }

    /// Awaits this card's queued/in-flight autosave write fully landing before returning. The editor's
    /// image-delete path calls this *after* enqueuing any un-debounced draft and *before* invoking
    /// `deleteMarkdownImage`, so the domain removes the reference from the body the autosave just
    /// persisted — not a baseline a later autosave snapshot (still carrying the reference) could
    /// clobber on the shared `mutate` flock (ticket 2A2784BE, PR #137 r2-1).
    func flushPendingMarkdownSave(_ cardID: UUID) async {
        await markdownAutosave.flush(cardID: cardID)
    }

    /// Persist closure backing `markdownAutosave`. Returns the error (or `nil` on success) so
    /// the queue can decide retry/surfacing; unlike `editCard` it does not set `self.error`
    /// itself — the queue surfaces failures once per card-streak, not once per retry.
    func persistMarkdown(cardID: UUID, content: String) async -> (any Error)? {
        do {
            try await applyEditedCard(EditCardRequest(cardID: cardID, markdownContent: content))
            return nil
        } catch {
            return error
        }
    }

    /// Write-ahead journal closure backing `markdownAutosave`: persists the latest text (+ the
    /// edit's `enqueuedAt`) to the durable journal before the real write is attempted (ticket
    /// 44C9D3C2). Best-effort — a journal write that itself fails must not block or fail the real
    /// write, so the error is swallowed here (the in-memory queue still drives the actual save +
    /// retry). The swallow is no longer silent: the store logs the write failure via the diagnostics
    /// sink before it surfaces here, so a permanently-failing journal (permissions, disk) is
    /// observable rather than the durability layer vanishing unseen (ticket 7DA7C85F).
    func journalMarkdown(cardID: UUID, content: String, enqueuedAt: Date) async {
        try? await markdownJournalUseCases.record.execute(
            RecordMarkdownJournalRequest(cardID: cardID, content: content, enqueuedAt: enqueuedAt)
        )
    }

    /// Clears a card's durable journal entry — after its write lands or the user discards it.
    /// Best-effort: a failed delete leaves a stale entry that a later launch re-applies. That
    /// re-apply is only idempotent with no other writer — an MCP `markdown_set` landing in between
    /// would be clobbered by the stale entry on the next launch — so the failure must be visible:
    /// the store logs a failed clear via the diagnostics sink before it surfaces here, where it is
    /// swallowed to keep the clear best-effort (ticket 7DA7C85F).
    func clearMarkdownJournal(cardID: UUID) async {
        try? await markdownJournalUseCases.clear.execute(ClearMarkdownJournalRequest(cardID: cardID))
    }

    /// Recomputes the observable map of cards with stranded unsaved edits (→ each edit's
    /// `enqueuedAt`) from the autosave channel. Called by the queue's `onUnsavedChange` sink so the
    /// editor's Retry/Discard banner re-renders.
    func refreshUnsavedMarkdown() {
        unsavedMarkdownEdits = markdownAutosave.unsavedEdits()
    }

    /// Re-attempt a stranded card's Markdown save (editor banner's Retry button).
    func retryMarkdownSave(cardID: UUID) {
        markdownAutosave.retry(cardID: cardID)
    }

    /// Drop a stranded card's unsaved Markdown edit and clear its journal (editor banner's Discard).
    func discardMarkdownSave(cardID: UUID) async {
        await markdownAutosave.discard(cardID: cardID)
    }

    /// Runs the `editCard` use case and publishes the result, rethrowing on failure. The shared
    /// happy path behind both `editCard` (which maps the throw to a `Bool` + `self.error`) and
    /// `persistMarkdown` (which hands the error to the autosave queue) — they differ only in
    /// error policy, so the persist+publish step is factored here.
    private func applyEditedCard(_ request: EditCardRequest) async throws {
        applyBoardMutation(try await kanbanUseCases.editCard.execute(request))
    }

    func moveCard(id: UUID, toColumn: UUID, before: UUID?) async {
        do {
            applyBoardMutation(try await kanbanUseCases.moveCard.execute(
                MoveCardRequest(cardID: id, toColumnID: toColumn, beforeCardID: before)
            ))
        } catch {
            self.error = error
        }
    }

    func deleteCard(id: UUID) async {
        do {
            applyBoard(try await kanbanUseCases.deleteCard.execute(DeleteCardRequest(cardID: id)))
        } catch {
            self.error = error
        }
    }
}
