import Foundation

final class CanvasImageService: CanvasImageServiceProtocol, Sendable {
    private let repository: any BoardRepositoryProtocol
    /// The image's pixel bytes persist out-of-band (a sidecar asset keyed by `assetID`). This
    /// service owns both the asset bytes and the on-canvas `CanvasImage` placement so the UseCase
    /// layer touches no Repository directly.
    private let imageAssetRepository: any ImageAssetRepositoryProtocol
    /// How recent is too recent to reclaim — the orphan GC's grace window. A domain policy, so it
    /// is injected rather than hard-coded; see `AssetGCPolicy`.
    private let gcPolicy: AssetGCPolicy
    /// Diagnostics port for the orphan-asset GC: a best-effort background sweep with no result
    /// channel, so its outcome (reclaimed count, per-file failures, reachability abort) would be
    /// invisible without this. See `sweepOrphanedAssets`.
    private let diagnostics: any DiagnosticsLoggingProtocol
    /// Injected clock so the GC's grace cutoff (`now - gracePeriod`) is deterministic in tests.
    private let now: @Sendable () -> Date

    init(repository: any BoardRepositoryProtocol,
         imageAssetRepository: any ImageAssetRepositoryProtocol,
         diagnostics: any DiagnosticsLoggingProtocol,
         gcPolicy: AssetGCPolicy = .default,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.imageAssetRepository = imageAssetRepository
        self.diagnostics = diagnostics
        self.gcPolicy = gcPolicy
        self.now = now
    }

    // MARK: Imperative verbs (own the mutate boundary)

    /// Persists the image bytes, then places a `CanvasImage` on the card's canvas. The bytes are
    /// saved **before** the board mutation, so a failed mutation leaves only an orphaned asset file
    /// (harmless), never a `CanvasImage` referencing missing pixels. The fitted size and source
    /// aspect ratio derive once from the natural dimensions so they cannot drift.
    func add(imageData: Data, naturalSize: NaturalSize,
             position: CanvasPosition, toCardCanvas cardID: Card.ID) async throws -> BoardState {
        let assetID = try await saveAsset(imageData: imageData)
        let fitted = fittedImage(naturalSize: naturalSize)
        let placement = ImagePlacement(position: position, size: fitted.size)
        let asset = ImageAssetRef(assetID: assetID, aspectRatio: fitted.aspectRatio)
        return try await repository.mutate { state in
            self.adding(asset: asset, placement: placement, toCardCanvas: cardID, in: state)
        }
    }

    func move(id: CanvasImage.ID, to position: CanvasPosition) async throws -> BoardState {
        try await repository.mutate { state in try self.moving(id: id, to: position, in: state) }
    }

    func resize(id: CanvasImage.ID, to placement: ImagePlacement) async throws -> BoardState {
        try await repository.mutate { state in try self.resizing(id: id, to: placement, in: state) }
    }

    func bringToFront(id: CanvasImage.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.bringingToFront(id: id, in: state) }
    }

    func sendToBack(id: CanvasImage.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.sendingToBack(id: id, in: state) }
    }

    func delete(id: CanvasImage.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.deleting(id: id, from: state) }
    }

    /// Deletes a Markdown image reference from a card: removes the **first** `kanvas-asset://<assetID>`
    /// reference from the card's body, then reclaims the asset bytes **iff** no card/Canvas placement
    /// on any board still references that id (a refcount: the cell-delete drops one reference and the
    /// bytes go only when it was the last). The body rewrite persists inside `mutate`; the
    /// reachability check + bytes delete run **after** (outside `withLock`, since they are async I/O,
    /// and against the just-persisted store so the count is current). Throws `notFound` when the card
    /// or the reference is absent — no phantom success to an MCP caller.
    func deleteMarkdownImage(cardID: Card.ID, assetID: UUID) async throws -> BoardState {
        let newState = try await repository.mutate { state in
            try self.removingMarkdownReference(to: assetID, fromCard: cardID, in: state)
        }
        // Reachability is computed against the persisted store (post-mutate), so the removed reference
        // is already gone from the count. If nothing else references the asset, reclaim its bytes now —
        // the user-initiated delete does not wait on the orphan GC. A still-referenced asset (another
        // card / board / Canvas placement, or a duplicate reference on this same card) keeps its bytes.
        let reachable = try await reachableAssetIDs()
        if !reachable.contains(assetID) {
            try await imageAssetRepository.delete(assetID: assetID)
        }
        return newState
    }

    /// Persists image bytes as a standalone sidecar asset and returns its id — no board mutation, so
    /// no undo entry. Same bytes-first store as `add` (which now delegates here); the Markdown editor
    /// references the id from the card body as `kanvas-asset://<id>`. A save left unreferenced (the
    /// body never persists the reference) is harmless — the orphan GC reclaims it after the grace
    /// window, exactly like `add`'s pre-mutation save.
    func saveAsset(imageData: Data) async throws -> UUID {
        let assetID = UUID()
        try await imageAssetRepository.save(assetID: assetID, data: imageData)
        return assetID
    }

    /// Reads an image asset's pixel bytes for display.
    func loadImageData(assetID: UUID) async throws -> Data {
        try await imageAssetRepository.load(assetID: assetID)
    }

    func sweepOrphanedAssets() async throws {
        // Candidates first: only assets older than the grace window, so a concurrent process that
        // just wrote bytes but has not yet committed its `CanvasImage` is excluded up front.
        let cutoff = now().addingTimeInterval(-gcPolicy.gracePeriod)
        let candidates: Set<UUID>
        do {
            candidates = try await imageAssetRepository.assetIDs(modifiedBefore: cutoff)
        } catch {
            // The last otherwise-silent throw path of a destructive op: the Presentation caller
            // swallows it (`try?`, best-effort), so without this the GC could fail to even enumerate
            // candidates every launch with zero trace. Nothing is deleted here, but the failure is
            // diagnosable. Mirrors the reachability-abort log below.
            diagnostics.log(
                "orphan-asset GC aborted: could not list aged candidate assets",
                privateDetail: "\(error)",
                level: .error
            )
            throw error
        }
        guard !candidates.isEmpty else { return }
        // Compute reachability across *every* board before deleting anything; `reachableAssetIDs`
        // rethrows on the first unreadable board, so a partial read aborts the whole sweep rather
        // than reclaiming an asset the unread board might reference. Surface that abort: a
        // permanently corrupt snapshot would otherwise make the GC silently reclaim nothing forever.
        let reachable: Set<UUID>
        do {
            reachable = try await reachableAssetIDs()
        } catch {
            diagnostics.log(
                "orphan-asset GC aborted: a board snapshot failed to load; reachability unknown, "
                    + "\(candidates.count) candidate(s) left untouched",
                privateDetail: "\(error)",
                level: .error
            )
            throw error
        }
        let orphans = candidates.subtracting(reachable)
        var reclaimed = 0
        var failed = 0
        for assetID in orphans {
            // Best-effort per file: a single undeletable asset (locked / permissions) must not block
            // reclaiming the rest of the batch, but a persistent failure is no longer silent.
            do {
                try await imageAssetRepository.delete(assetID: assetID)
                reclaimed += 1
            } catch {
                failed += 1
                diagnostics.log("orphan-asset GC: failed to delete asset \(assetID)",
                                privateDetail: "\(error)", level: .error)
            }
        }
        // Report all three numbers: reclaimed vs. orphan count (reachability-excluded) vs. the wider
        // candidate count (aged assets examined) — the exact signal the GC exists to surface.
        diagnostics.log(
            "orphan-asset GC: reclaimed \(reclaimed) of \(orphans.count) orphan(s) "
                + "(\(candidates.count) candidate(s) examined)"
                + (failed > 0 ? ", \(failed) failed" : ""),
            level: failed > 0 ? .error : .info
        )
    }

    /// Union of every `assetID` reachable on any board — through **two** reference paths, both of
    /// which keep the asset alive:
    /// - a `CanvasImage` placement on a card's canvas (`assetID`), and
    /// - a `kanvas-asset://<id>` reference embedded in any card's `markdownContent` (the Markdown
    ///   editor's inline images — the *only* thing that keeps a Markdown-dropped asset reachable,
    ///   since it places no `CanvasImage`). Missing this union would let the GC reclaim a pasted
    ///   Markdown image the moment its grace window passed — the correctness hinge of ticket BF5746C8.
    ///
    /// Reads the whole catalog under one lock (`loadAllBoardStates`). That read is per-record
    /// fail-open, but reachability must be *complete*: if any board snapshot won't decode, the
    /// reachable set is partial and a referenced asset could look orphaned, so any unreadable board
    /// makes this throw "reachability unknown" — the caller treats that as abort-don't-delete.
    private func reachableAssetIDs() async throws -> Set<UUID> {
        let (states, unreadableBoardIDs) = try await repository.loadAllBoardStates()
        // Not `fileCorrupted`: the read *succeeded*: reachability is merely incomplete. Name the
        // undecodable boards so the GC's abort log can be correlated to them (the repo also logs
        // each id separately, but this keeps the single abort line self-describing).
        guard unreadableBoardIDs.isEmpty else {
            throw OperationError.inconsistentState(
                reason: "reachability unknown: \(unreadableBoardIDs.count) board(s) undecodable "
                    + "(\(unreadableBoardIDs.map(\.uuidString).joined(separator: ", ")))")
        }
        var reachable: Set<UUID> = []
        for state in states {
            reachable.formUnion(state.images.map(\.assetID))
            for card in state.cards {
                reachable.formUnion(MarkdownImageReference.referencedAssetIDs(in: card.markdownContent))
            }
        }
        return reachable
    }

    // MARK: Pure transforms

    func adding(asset: ImageAssetRef, placement: ImagePlacement,
                toCardCanvas cardID: Card.ID, in state: BoardState) -> BoardState {
        var state = state
        let image = CanvasImage(
            cardID: cardID,
            assetID: asset.assetID,
            position: placement.position,
            size: placement.size,
            aspectRatio: asset.aspectRatio,
            sortIndex: state.nextFrontCanvasIndex(forCard: cardID)
        )
        state.images.append(image)
        return state
    }

    func moving(id: CanvasImage.ID, to position: CanvasPosition, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.images, entityKind: "Image")
        state.images[idx].position = position
        return state
    }

    func resizing(id: CanvasImage.ID, to placement: ImagePlacement, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.images, entityKind: "Image")
        // Preserve aspect ratio: trust the new width, derive the height from the stored ratio.
        // The canvas resize handle feeds an arbitrary box; this keeps the image from distorting.
        let ratio = state.images[idx].aspectRatio
        let width = placement.size.width
        state.images[idx].size = ImageSize(width: width, height: width / ratio)
        state.images[idx].position = placement.position
        return state
    }

    func bringingToFront(id: CanvasImage.ID, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.images, entityKind: "Image")
        let cardID = state.images[idx].cardID
        // Shared canvas z-order: front of *all* items (stickies + shapes + images).
        state.images[idx].sortIndex = state.nextFrontCanvasIndex(forCard: cardID, excluding: id)
        return state
    }

    func sendingToBack(id: CanvasImage.ID, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.images, entityKind: "Image")
        let cardID = state.images[idx].cardID
        state.images[idx].sortIndex = state.nextBackCanvasIndex(forCard: cardID, excluding: id)
        return state
    }

    func deleting(id: CanvasImage.ID, from state: BoardState) throws -> BoardState {
        guard state.images.contains(where: { $0.id == id }) else {
            throw OperationError.notFound(entityKind: "Image", id: id)
        }
        var state = state
        // Only the canvas item is removed; the sidecar asset file is intentionally left in place
        // so an undo can restore the item. An asset orphaned this way is reclaimed by the startup
        // GC (`sweepOrphanedAssets`) once no board references it, never eagerly here.
        state.images.removeAll { $0.id == id }
        return state
    }

    /// Pure: removes the first `kanvas-asset://<assetID>` reference from the card's `markdownContent`.
    /// Resolves the card via `requireIndex` (throws `notFound(.Card)` when absent) and throws
    /// `notFound(.Image)` when the body carries no reference to that id — so an MCP caller never gets a
    /// phantom success for a missing card or reference. The bytes reclaim happens in the imperative
    /// verb, after persistence; this transform only touches the body text.
    func removingMarkdownReference(to assetID: UUID, fromCard cardID: Card.ID,
                                   in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: cardID, in: \.cards, entityKind: "Card")
        guard let newBody = MarkdownImageReference.removingFirstReference(
            to: assetID, in: state.cards[idx].markdownContent
        ) else {
            throw OperationError.notFound(entityKind: "Image", id: assetID)
        }
        state.cards[idx].markdownContent = newBody
        return state
    }

    func fittedImage(naturalSize: NaturalSize) -> (size: ImageSize, aspectRatio: Double) {
        let naturalWidth = naturalSize.width
        let naturalHeight = naturalSize.height
        let ratio = naturalWidth > 0 && naturalHeight > 0 ? naturalWidth / naturalHeight : 1
        let maxSide = ImageSize.defaultMaxSide
        // Scale the longer side down to `maxSide` (never up — a small image keeps its size).
        let size: ImageSize = naturalWidth >= naturalHeight
            ? ImageSize(width: min(naturalWidth, maxSide), height: min(naturalWidth, maxSide) / ratio)
            : ImageSize(width: min(naturalHeight, maxSide) * ratio, height: min(naturalHeight, maxSide))
        return (size, ratio)
    }
}
