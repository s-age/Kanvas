import Foundation

// MARK: - Image Actions

extension BoardViewModel {

    /// Adds a pasted/dropped image to the selected card's canvas. The use case persists the PNG
    /// bytes as a sidecar asset and adds the placement; the refreshed card detail then carries the
    /// new image, which the canvas draws (fetching the bytes back lazily via `loadImageData`).
    func addImage(cardID: UUID, x: Double, y: Double, payload: CanvasImagePayload) async {
        do {
            applyBoardMutation(try await imageUseCases.add.execute(
                AddImageRequest(
                    cardID: cardID, imageData: payload.pngData,
                    positionX: x, positionY: y,
                    naturalWidth: payload.naturalWidth, naturalHeight: payload.naturalHeight
                )
            ))
        } catch {
            self.error = error
        }
    }

    /// Saves a dropped image's PNG bytes as a sidecar asset and returns its id, **without** placing a
    /// `CanvasImage` — the Markdown editor's inline-image import. The caller embeds the id in the card
    /// body as `kanvas-asset://<id>` (kept reachable by the orphan GC's Markdown scan). Returns `nil`
    /// on failure (surfaced via `error`), so the editor inserts no broken reference.
    func addMarkdownImage(payload: CanvasImagePayload) async -> UUID? {
        do {
            return try await imageUseCases.saveAsset.execute(
                SaveImageAssetRequest(imageData: payload.pngData)
            ).assetID
        } catch {
            self.error = error
            return nil
        }
    }

    /// Deletes a Markdown inline image referenced by the open card's body: the use case removes the
    /// first `kanvas-asset://<assetID>` reference and reclaims the bytes when no board references the
    /// asset any more (refcount — a duplicate reference or a Canvas placement keeps it). Applies the
    /// returned mutation (so `selectedCardDetail` reflects the rewritten body) and hands the refreshed
    /// body back to the editor so it can re-seed its draft from the single domain-owned result.
    /// Returns `nil` on failure (surfaced via `error`), so the editor leaves its draft untouched.
    func deleteMarkdownImage(cardID: UUID, assetID: UUID) async -> String? {
        do {
            let mutation = try await imageUseCases.deleteMarkdownImage.execute(
                DeleteMarkdownImageRequest(cardID: cardID, assetID: assetID)
            )
            applyBoardMutation(mutation)
            // Prefer the detail the mutation carried for this card; fall back to the freshly-adopted
            // `selectedCardDetail` when it is the open card (it is, in the editor's flow).
            if let detail = mutation.cardDetail, detail.id == cardID { return detail.markdownContent }
            return selectedCardDetail?.id == cardID ? selectedCardDetail?.markdownContent : nil
        } catch {
            self.error = error
            return nil
        }
    }

    func moveImage(id: UUID, x: Double, y: Double) async {
        do {
            applyBoardMutation(try await imageUseCases.move.execute(
                MoveImageRequest(imageID: id, positionX: x, positionY: y)
            ))
        } catch {
            self.error = error
        }
    }

    /// `frame` is the image's new world-space bounding rect; size + centre commit as one atomic
    /// mutation. The use case re-derives the height from the source aspect ratio, so the committed
    /// size matches the aspect-locked resize preview.
    func resizeImage(id: UUID, frame: CGRect) async {
        do {
            applyBoardMutation(try await imageUseCases.resize.execute(
                ResizeImageRequest(
                    imageID: id,
                    width: Double(frame.width), height: Double(frame.height),
                    positionX: Double(frame.midX), positionY: Double(frame.midY)
                )
            ))
        } catch {
            self.error = error
        }
    }

    func bringImageToFront(id: UUID) async {
        do {
            applyBoardMutation(try await imageUseCases.bringToFront.execute(BringImageToFrontRequest(imageID: id)))
        } catch {
            self.error = error
        }
    }

    func sendImageToBack(id: UUID) async {
        do {
            applyBoardMutation(try await imageUseCases.sendToBack.execute(SendImageToBackRequest(imageID: id)))
        } catch {
            self.error = error
        }
    }

    func deleteImage(id: UUID) async {
        await applyCanvasDelete(id: id) {
            try await imageUseCases.delete.execute(DeleteImageRequest(imageID: id, cardID: selectedCardID))
        }
    }

    /// Reads a placed image's PNG bytes for the canvas to decode + draw. Maps the outcome to
    /// `CanvasImageLoad` so the canvas can tell a *terminal* miss (genuinely absent asset → keep the
    /// placeholder, never re-fetch) from a *transient* one (a read fault during an external atomic
    /// replace, or a cancelled `.task` fetch → retry next redraw). No alert either way: a draw-time
    /// fetch is not a user action awaiting a result. `loadFailed` is the store's "file absent" signal;
    /// any other error (or cancellation) is treated as transient (ticket 37B774CD).
    func loadImageData(assetID: UUID) async -> CanvasImageLoad {
        do {
            return .loaded(try await imageUseCases.loadData.execute(assetID: assetID))
        } catch OperationError.loadFailed {
            return .unavailable
        } catch {
            return .transientFailure
        }
    }

    /// Diagnostics only: the canvas permanently could not show a placed image and has negative-cached
    /// it. Forwards to the fire-and-forget logging use case so the placeholder's reason reaches
    /// Console — Presentation cannot reach the diagnostics port directly.
    func reportImageLoadFailure(assetID: UUID, reason: ImageLoadFailureReason) {
        imageUseCases.reportLoadFailure.execute(assetID: assetID, reason: reason)
    }

    /// Publishes a new image-preview target onto the shared state, stamping the monotonic open
    /// generation (ticket 8511D150). The Markdown gallery calls this on a thumbnail tap (then opens
    /// the reusable preview window via `openWindow`); the gallery owns `boardWindowSize` because it
    /// lives in the AppKit carve-out that may read the board window's frame. Stamping here makes a
    /// same-image reopen during the dismiss animation a *distinct* value, so the closing window's
    /// identity-gated teardown (`clearMarkdownImagePreview(ifMatching:)`) does not wipe the reopened
    /// target blank.
    func openMarkdownImagePreview(assetIDs: [UUID], currentIndex: Int, boardWindowSize: CGSize) {
        markdownImagePreviewGeneration += 1
        markdownImagePreview = MarkdownImagePreviewRequest(
            assetIDs: assetIDs,
            currentIndex: currentIndex,
            boardWindowSize: boardWindowSize,
            generation: markdownImagePreviewGeneration
        )
    }

    /// Steps the open preview to the neighbouring asset in the ordered set (Lightbox navigation,
    /// ticket B23D376B). `delta` is +1 (next) or -1 (previous); the new index is clamped to
    /// `assetIDs`' bounds, so a step past the first/last asset is a no-op (no looping — the ticket's
    /// 端の扱い). Re-stamps the monotonic open `generation` so the resulting request stays a distinct
    /// value (consistent with `openMarkdownImagePreview`), and the preview window's `task(id:)`
    /// re-decodes the new `currentAssetID` and re-fits zoom/pan. A no-op when no preview is open.
    func stepMarkdownImagePreview(by delta: Int) {
        guard let current = markdownImagePreview else { return }
        let target = current.currentIndex + delta
        guard current.assetIDs.indices.contains(target) else { return }
        markdownImagePreviewGeneration += 1
        markdownImagePreview = MarkdownImagePreviewRequest(
            assetIDs: current.assetIDs,
            currentIndex: target,
            boardWindowSize: current.boardWindowSize,
            generation: markdownImagePreviewGeneration
        )
    }

    /// Clears the shared preview target only if it still equals `snapshot` — the preview window's
    /// single teardown verb. Both close routes (Esc and the title-bar button) end with the window
    /// vanishing; its `onDisappear` calls this with the request it was showing. If a fresh open (even
    /// of the same image) published a newer request while the dismiss animation was in flight, the
    /// live value's `generation` has advanced past the snapshot, so the gate fails and the reopened
    /// target survives instead of being wiped by the stale teardown.
    func clearMarkdownImagePreview(ifMatching snapshot: MarkdownImagePreviewRequest?) {
        if markdownImagePreview == snapshot {
            markdownImagePreview = nil
        }
    }

    /// Reclaims orphaned sidecar assets, **once per launch** and fully best-effort: a GC failure is
    /// background maintenance no user is awaiting, so any error (including cancellation) is
    /// swallowed rather than promoted to `error`. Driven by `performStartupMaintenance()` (not
    /// `load()`, which must stay read-only), so it runs at startup where the undo ring is empty —
    /// see `hasSweptOrphanAssets`.
    func sweepOrphanedImageAssets() async {
        guard !hasSweptOrphanAssets else { return }
        hasSweptOrphanAssets = true
        try? await imageUseCases.sweepOrphans.execute()
    }
}
