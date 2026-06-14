import SwiftUI

struct MarkdownEditorView: View {
    @Bindable var viewModel: BoardViewModel
    @State private var draft = ""
    /// The autosave baseline `save()` diffs the draft against — `draft == loadedContent` means
    /// "this text was already handed to the autosave channel, nothing new to enqueue". `save()`
    /// advances it to the text it enqueues; the channel (`BoardViewModel.markdownAutosave`) owns
    /// persistence and retry from here, so this is a de-dup baseline, not a guarantee of disk
    /// state. The authoritative "is there an unsaved edit?" signal is `hasPendingMarkdownSave`.
    @State private var loadedContent = ""
    /// Captured separately from `selectedCardID` so a back-navigation (which nils
    /// `selectedCardID` *before* `onDisappear`) can still persist the final edit.
    /// Written **only** in `load(id:content:)` — do not add other write points, or this
    /// second source of card identity will drift from `selectedCardDetail?.id`.
    @State private var editingCardID: UUID?
    @State private var autosaveTask: Task<Void, Never>?
    /// Asset ids the gallery shows, derived from `draft`. Cached in `@State` and recomputed only when
    /// `draft` actually changes (not on every `body` re-eval), so the per-card `Regex` scan in
    /// `MarkdownImageReference.referencedAssetIDs` does not run on unrelated re-renders.
    @State private var galleryAssetIDs: [UUID] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardMetadataEditor(viewModel: viewModel)
            Divider()
            Text("Notes")
                .font(.headline)
            unsavedBanner
            MarkdownTextView(
                text: $draft,
                settings: viewModel.board?.settings.markdown,
                global: viewModel.board?.settings.global,
                onEndEditing: { save() },
                saveDroppedImage: { await viewModel.addMarkdownImage(payload: $0) }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Skip arming the debounce when the draft just snapped to the persisted baseline (card
                // load or external re-seed) — save() would no-op anyway. Always refresh the gallery's
                // id set, so a dropped/pasted reference (or an external rewrite) is reflected at once.
                .onChange(of: draft) {
                    if draft != loadedContent { scheduleAutosave() }
                    galleryAssetIDs = referencedAssetIDs(in: draft)
                }
            // The card's `kanvas-asset://` images render here, in a horizontal fixed-height strip — NOT
            // inline in the NSTextView, whose attachment layout crashed (ticket 04568CD4).
            MarkdownImageGallery(
                assetIDs: galleryAssetIDs,
                loadImageData: { await viewModel.loadImageData(assetID: $0) },
                reportImageLoadFailure: { viewModel.reportImageLoadFailure(assetID: $0, reason: $1) },
                deleteImage: { deleteImage(assetID: $0) },
                setPreview: { viewModel.openMarkdownImagePreview(assetIDs: $0, currentIndex: $1, boardWindowSize: $2) }
            )
        }
        .padding()
        .onAppear {
            load(id: viewModel.selectedCardDetail?.id ?? viewModel.selectedCardID,
                 content: viewModel.selectedCardDetail?.markdownContent ?? "")
        }
        .onChange(of: viewModel.selectedCardDetail?.id) { _, newID in
            // Ignore the clear-to-nil on dismissal so the draft survives until onDisappear.
            guard let newID else { return }
            // Switching to a different card: persist the outgoing one *before* its draft and
            // id are overwritten, otherwise an un-debounced edit to the previous card is lost.
            if newID != editingCardID { flushPending() }
            load(id: newID, content: viewModel.selectedCardDetail?.markdownContent ?? "")
        }
        // The notes have an external writer by design — `markdown_set` (MCP) can rewrite the
        // *currently-open* card, and `BoardStoreWatcher` reloads `selectedCardDetail` with the
        // card id unchanged, so the id-keyed onChange above never re-runs (same situation as
        // `CardMetadataEditor`'s prURL). Re-seed the draft only when there is no unsaved local
        // edit (`draft == loadedContent`); a dirty draft keeps local — its autosave wins.
        .onChange(of: viewModel.selectedCardDetail?.markdownContent) { _, newContent in
            guard let newContent,
                  ExternalNotesRewrite(
                      newContent: newContent,
                      detailCardID: viewModel.selectedCardDetail?.id,
                      editingCardID: editingCardID,
                      draft: draft,
                      loadedContent: loadedContent,
                      hasPendingSave: editingCardID.map { viewModel.hasPendingMarkdownSave($0) } ?? false
                  ).shouldAdopt
            else { return }
            draft = newContent
            loadedContent = newContent
        }
        .onDisappear { flushPending() }
    }

    /// Pure gate for the external-rewrite re-seed above, extracted as a value so the merge
    /// policy is unit-testable (it is otherwise unreachable from a headless ViewModel test).
    /// Adopt only genuinely new content — not our own save echoing back through the watcher
    /// (`newContent == loadedContent`) — for the card being edited, and only while the buffer
    /// is clean: no draft edit beyond the baseline (`draft == loadedContent`) **and** nothing
    /// still owed to the disk by the autosave channel (`!hasPendingSave`). A pending save can
    /// outlive `draft == loadedContent` (the baseline advances when text is enqueued, before
    /// the write lands), so the channel's pending flag is the authoritative dirty signal.
    struct ExternalNotesRewrite {
        let newContent: String
        let detailCardID: UUID?
        let editingCardID: UUID?
        let draft: String
        let loadedContent: String
        let hasPendingSave: Bool

        var shouldAdopt: Bool {
            detailCardID != nil && detailCardID == editingCardID
                && newContent != loadedContent
                && draft == loadedContent
                && !hasPendingSave
        }
    }

    /// Asset ids `body` references (`kanvas-asset://<id>`), first-appearance order, deduplicated —
    /// drives `MarkdownImageGallery`. Each id's first offset is computed once (case-insensitive: a
    /// hand-edited / MCP-written reference may carry a lowercase id) and reused across the sort, so
    /// ordering is O(n) offset lookups + one sort, not a search inside every comparison.
    private func referencedAssetIDs(in body: String) -> [UUID] {
        let ids = MarkdownImageReference.referencedAssetIDs(in: body)
        guard !ids.isEmpty else { return [] }
        let firstOffset = Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, body.range(of: id.uuidString, options: .caseInsensitive)?.lowerBound ?? body.endIndex)
        })
        return ids.sorted { (firstOffset[$0] ?? body.endIndex) < (firstOffset[$1] ?? body.endIndex) }
    }

    private func load(id: UUID?, content: String) {
        // A detail arriving for the card we're *already* editing must not clobber text the
        // user typed during the brief async-load window. Guard only when the stored content
        // is empty, so a stray early keystroke can never overwrite real saved notes — if the
        // card actually has content, it wins (losing a few ms of typing beats data loss).
        if id == editingCardID, content.isEmpty, !draft.isEmpty { return }
        editingCardID = id
        draft = content
        loadedContent = content
        galleryAssetIDs = referencedAssetIDs(in: content)
    }

    /// Cancel any pending autosave and persist the current draft now. Used on disappear and
    /// before a card switch replaces `editingCardID`/`draft` — both read here before the swap.
    private func flushPending() {
        autosaveTask?.cancel()
        save()
    }

    /// Debounced autosave so edits persist even without an explicit focus loss.
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        // `@MainActor` so `save()` (which mutates `@State`) runs on the main actor — a bare
        // `Task` inherits no isolation here (the View is not `@MainActor`, only `body` is).
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// Banner shown when the autosave channel gave up persisting this card's edit after a
    /// *retainable* failure (disk full, lock contention) — the durable journal still holds the
    /// text (ticket 44C9D3C2). Lets the user force a Retry or Discard the stranded edit. Absent
    /// for a clean card, so it costs nothing in the common path.
    @ViewBuilder
    private var unsavedBanner: some View {
        if let cardID = editingCardID, let since = viewModel.unsavedMarkdownEdits[cardID] {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Unsaved since \(since.formatted(date: .omitted, time: .shortened)) — kept, will retry.")
                    .font(.callout)
                Spacer()
                Button("Retry") { viewModel.retryMarkdownSave(cardID: cardID) }
                Button("Discard") { discardUnsaved(cardID: cardID) }
            }
            .padding(8)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Drop this card's stranded unsaved edit and re-seed the editor from the persisted content,
    /// so the buffer matches disk again.
    private func discardUnsaved(cardID: UUID) {
        Task { @MainActor in
            await viewModel.discardMarkdownSave(cardID: cardID)
            let persisted = viewModel.selectedCardDetail?.markdownContent ?? ""
            draft = persisted
            loadedContent = persisted
        }
    }

    /// Deletes a Markdown inline image referenced by the gallery (the hover delete button). The Domain
    /// is the **single owner** of "which reference to remove" — the editor never edits its own draft to
    /// strip the reference (that would risk a double removal against the domain's). The procedure:
    /// 1. Enqueue any un-debounced draft (`save()`), then **await** it fully landing
    ///    (`flushPendingMarkdownSave`) — both the delete and the autosave persist the body through the
    ///    same `BoardRepository.mutate` flock, with no ordering guarantee between them. If the delete
    ///    fired first it would strip the reference (reclaiming the bytes), then a still-queued autosave
    ///    snapshot of the *un-deleted* body would rewrite the reference back — a reference whose bytes
    ///    are gone (the missing-asset state the refcount design forbids). Awaiting the autosave to land
    ///    first means the domain removes the reference from the body the autosave just persisted, on a
    ///    baseline the queue is no longer about to overwrite (ticket 2A2784BE, PR #137 r2-1).
    /// 2. `deleteMarkdownImage` removes the first reference (and reclaims the bytes when nothing else
    ///    references the asset) and returns the rewritten body.
    /// 3. Re-seed `draft` + `loadedContent` from that body so the editor and gallery reflect it without
    ///    re-arming the autosave (the re-seed sets `draft == loadedContent`).
    private func deleteImage(assetID: UUID) {
        guard let cardID = editingCardID else { return }
        Task { @MainActor in
            autosaveTask?.cancel()
            save()
            await viewModel.flushPendingMarkdownSave(cardID)
            guard let refreshed = await viewModel.deleteMarkdownImage(cardID: cardID, assetID: assetID)
            else { return }
            draft = refreshed
            loadedContent = refreshed
            galleryAssetIDs = referencedAssetIDs(in: refreshed)
        }
    }

    private func save() {
        guard let cardID = editingCardID, draft != loadedContent else { return }
        // Advance the de-dup baseline to the text we hand off so a focus-loss save chasing the
        // same content no-ops against this one. Persistence, ordering, and retry now belong to
        // the autosave channel (`BoardViewModel.markdownAutosave`): `enqueue` is synchronous and
        // the channel lives on the ViewModel, so a write fired from `onDisappear` still lands and
        // retries on failure even though this view is gone — no in-view rollback needed.
        loadedContent = draft
        viewModel.enqueueMarkdownSave(cardID: cardID, content: draft)
    }
}
