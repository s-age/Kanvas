import Foundation

// The UseCase layer's full contract surface, consolidated into one file per layer (the layer
// boundary is the meaningful grouping unit — one read shows every contract). Most use cases are
// existential typealiases over `AsyncUseCase<Request, Response>`; the few that don't fit that shape
// (no request, or an optional/non-`BoardResponse` return) are standalone protocols at the bottom.

// MARK: - Base

/// Base contract every kanvas use case conforms to. kanvas is async-only, and the suspension is
/// real — not async-in-name. The load-bearing reason is *not* "every `execute` awaits a Domain
/// Service" (an `async` call can return without ever suspending): it is that every store-reaching
/// use case awaits store I/O that is offloaded onto a real thread, so the caller genuinely suspends
/// and its cooperative-pool thread is freed. That is the "does this need to suspend?" test that
/// makes `AsyncUseCase` the correct base over `SyncUseCase`. The offload mechanism is an
/// Infrastructure detail owned a layer down — see
/// `knowledge/architecture/syncusecase-by-suspension-not-io.md` and the
/// `asyncusecase-suspension-needs-offload.md` gotcha rather than restating it here.
///
/// "Reaches a store" is the qualifier, not "every `execute` suspends" flatly: a stream-returning
/// `AsyncUseCase` is correctly async while its `execute` does not itself suspend — suspension moves
/// to the stream's consumer (`syncusecase-returning-asyncstream.md`). kanvas has none today, so
/// every current use case suspends in `execute`. Either way the `SyncUseCase` /
/// `ValidationSyncUseCaseDecorator` pair described in arch-usecase.md is intentionally omitted —
/// there are zero synchronous use cases. Add it alongside the first one rather than carrying
/// untested dead code.
protocol AsyncUseCase<Request, Response>: Sendable {
    associatedtype Request: UseCaseRequest
    associatedtype Response
    func execute(_ request: Request) async throws -> Response
}

// MARK: - Board & catalog

typealias AddBoardUseCase = any AsyncUseCase<AddBoardRequest, BoardResponse>
typealias DeleteBoardUseCase = any AsyncUseCase<DeleteBoardRequest, BoardResponse>
typealias ListBoardsUseCase = any AsyncUseCase<ListBoardsRequest, BoardListResponse>
typealias LoadActiveBoardUseCase = any AsyncUseCase<LoadActiveBoardRequest, BoardResponse>
/// Combined board refresh: board + picker list + open-card detail from one store read (ticket 8DCB811D).
typealias LoadBoardViewStateUseCase = any AsyncUseCase<LoadBoardViewStateRequest, BoardViewStateResponse>
typealias LoadBoardByIDUseCase = any AsyncUseCase<LoadBoardByIDRequest, BoardResponse>
typealias RenameBoardUseCase = any AsyncUseCase<RenameBoardRequest, BoardListResponse>
typealias SwitchBoardUseCase = any AsyncUseCase<SwitchBoardRequest, BoardResponse>
typealias UndoUseCase = any AsyncUseCase<UndoRequest, UndoResponse>
typealias EditBoardSettingsUseCase = any AsyncUseCase<EditBoardSettingsRequest, BoardResponse>
typealias EditBoardTemplateUseCase = any AsyncUseCase<EditBoardTemplateRequest, BoardTemplateResponse>

// MARK: - Column

typealias AddColumnUseCase = any AsyncUseCase<AddColumnRequest, BoardResponse>
typealias DeleteColumnUseCase = any AsyncUseCase<DeleteColumnRequest, BoardResponse>
typealias RenameColumnUseCase = any AsyncUseCase<RenameColumnRequest, BoardResponse>
typealias ReorderColumnUseCase = any AsyncUseCase<ReorderColumnRequest, BoardResponse>
typealias SetCompletionColumnUseCase = any AsyncUseCase<SetCompletionColumnRequest, BoardResponse>
typealias EditColumnAppearanceUseCase = any AsyncUseCase<EditColumnAppearanceRequest, BoardResponse>

// MARK: - Card

typealias AddCardUseCase = any AsyncUseCase<AddCardRequest, AddCardResponse>
typealias EditCardUseCase = any AsyncUseCase<EditCardRequest, BoardMutationResponse>
typealias MoveCardUseCase = any AsyncUseCase<MoveCardRequest, BoardMutationResponse>
typealias DeleteCardUseCase = any AsyncUseCase<DeleteCardRequest, BoardResponse>

// MARK: - Sticky

typealias AddStickyUseCase = any AsyncUseCase<AddStickyRequest, BoardMutationResponse>
typealias EditStickyUseCase = any AsyncUseCase<EditStickyRequest, BoardMutationResponse>
typealias MoveStickyUseCase = any AsyncUseCase<MoveStickyRequest, BoardMutationResponse>
typealias SetStickyFrameUseCase = any AsyncUseCase<SetStickyFrameRequest, BoardMutationResponse>
typealias DuplicateStickyUseCase = any AsyncUseCase<DuplicateStickyRequest, BoardMutationResponse>
typealias DeleteStickyUseCase = any AsyncUseCase<DeleteStickyRequest, BoardMutationResponse>
typealias PromoteStickyUseCase = any AsyncUseCase<PromoteStickyRequest, BoardMutationResponse>
typealias DemoteStickyUseCase = any AsyncUseCase<DemoteStickyRequest, BoardMutationResponse>
typealias ToggleStickyLabelUseCase = any AsyncUseCase<ToggleStickyLabelRequest, BoardMutationResponse>
typealias BringStickyToFrontUseCase = any AsyncUseCase<BringStickyToFrontRequest, BoardMutationResponse>
typealias SendStickyToBackUseCase = any AsyncUseCase<SendStickyToBackRequest, BoardMutationResponse>
typealias SetStickyFillColorUseCase = any AsyncUseCase<SetStickyFillColorRequest, BoardMutationResponse>
typealias SetStickyFontSizeUseCase = any AsyncUseCase<SetStickyFontSizeRequest, BoardMutationResponse>
typealias SetStickyTextColorUseCase = any AsyncUseCase<SetStickyTextColorRequest, BoardMutationResponse>

// MARK: - Connector

typealias AddConnectorUseCase = any AsyncUseCase<AddConnectorRequest, BoardMutationResponse>
typealias DeleteConnectorUseCase = any AsyncUseCase<DeleteConnectorRequest, BoardMutationResponse>
typealias SetConnectorCapUseCase = any AsyncUseCase<SetConnectorCapRequest, BoardMutationResponse>
typealias SetConnectorRoutingUseCase = any AsyncUseCase<SetConnectorRoutingRequest, BoardMutationResponse>
typealias SetConnectorStrokeColorUseCase = any AsyncUseCase<SetConnectorStrokeColorRequest, BoardMutationResponse>
typealias SetConnectorStrokeWidthUseCase = any AsyncUseCase<SetConnectorStrokeWidthRequest, BoardMutationResponse>
typealias SetConnectorStyleUseCase = any AsyncUseCase<SetConnectorStyleRequest, BoardMutationResponse>
typealias ReconnectConnectorUseCase = any AsyncUseCase<ReconnectConnectorRequest, BoardMutationResponse>
typealias SetConnectorWaypointUseCase = any AsyncUseCase<SetConnectorWaypointRequest, BoardMutationResponse>

// MARK: - Shape

typealias AddShapeUseCase = any AsyncUseCase<AddShapeRequest, BoardMutationResponse>
typealias MoveShapeUseCase = any AsyncUseCase<MoveShapeRequest, BoardMutationResponse>
typealias ResizeShapeUseCase = any AsyncUseCase<ResizeShapeRequest, BoardMutationResponse>
typealias DeleteShapeUseCase = any AsyncUseCase<DeleteShapeRequest, BoardMutationResponse>
typealias BringShapeToFrontUseCase = any AsyncUseCase<BringShapeToFrontRequest, BoardMutationResponse>
typealias SendShapeToBackUseCase = any AsyncUseCase<SendShapeToBackRequest, BoardMutationResponse>
typealias SetShapeFillColorUseCase = any AsyncUseCase<SetShapeFillColorRequest, BoardMutationResponse>
typealias SetShapeStrokeColorUseCase = any AsyncUseCase<SetShapeStrokeColorRequest, BoardMutationResponse>
typealias SetShapeStrokeWidthUseCase = any AsyncUseCase<SetShapeStrokeWidthRequest, BoardMutationResponse>

// MARK: - Text (free-text canvas objects)

typealias AddTextUseCase = any AsyncUseCase<AddTextRequest, BoardMutationResponse>
typealias DuplicateTextUseCase = any AsyncUseCase<DuplicateTextRequest, BoardMutationResponse>
typealias EditTextUseCase = any AsyncUseCase<EditTextRequest, BoardMutationResponse>
typealias MoveTextUseCase = any AsyncUseCase<MoveTextRequest, BoardMutationResponse>
typealias ResizeTextUseCase = any AsyncUseCase<ResizeTextRequest, BoardMutationResponse>
typealias DeleteTextUseCase = any AsyncUseCase<DeleteTextRequest, BoardMutationResponse>
typealias SetTextColorUseCase = any AsyncUseCase<SetTextColorRequest, BoardMutationResponse>
typealias SetTextFontSizeUseCase = any AsyncUseCase<SetTextFontSizeRequest, BoardMutationResponse>
typealias BringTextToFrontUseCase = any AsyncUseCase<BringTextToFrontRequest, BoardMutationResponse>
typealias SendTextToBackUseCase = any AsyncUseCase<SendTextToBackRequest, BoardMutationResponse>

// MARK: - Image

typealias AddImageUseCase = any AsyncUseCase<AddImageRequest, BoardMutationResponse>
typealias MoveImageUseCase = any AsyncUseCase<MoveImageRequest, BoardMutationResponse>
typealias ResizeImageUseCase = any AsyncUseCase<ResizeImageRequest, BoardMutationResponse>
typealias DeleteImageUseCase = any AsyncUseCase<DeleteImageRequest, BoardMutationResponse>
typealias BringImageToFrontUseCase = any AsyncUseCase<BringImageToFrontRequest, BoardMutationResponse>
typealias SendImageToBackUseCase = any AsyncUseCase<SendImageToBackRequest, BoardMutationResponse>
/// Saves image bytes as a sidecar asset and returns its id, **without** placing a `CanvasImage` —
/// the Markdown editor's drag-drop import path. The reference lives only as body text
/// (`kanvas-asset://<id>`), so the board is not mutated; hence a bespoke `SaveImageAssetResponse`
/// (just the id) rather than a `BoardMutationResponse`.
typealias SaveImageAssetUseCase = any AsyncUseCase<SaveImageAssetRequest, SaveImageAssetResponse>
/// Deletes a Markdown inline image from a card: removes the first body reference and reclaims the
/// asset bytes iff no board still references it (refcount). Unlike `SaveImageAssetUseCase`, this
/// *does* mutate the board (the card body), so it returns a `BoardMutationResponse`.
typealias DeleteMarkdownImageUseCase = any AsyncUseCase<DeleteMarkdownImageRequest, BoardMutationResponse>

// MARK: - Canvas group (multi-select)
//
// Group move / delete over a multi-selection, applied as ONE batch mutation (one undo entry) — see
// `CanvasGroupServiceProtocol` (ticket 4FF14DCF). Ids may name stickies / shapes / images /
// connectors; the kind is resolved in the Domain layer.

typealias MoveCanvasGroupUseCase = any AsyncUseCase<MoveCanvasGroupRequest, BoardMutationResponse>
typealias DeleteCanvasGroupUseCase = any AsyncUseCase<DeleteCanvasGroupRequest, BoardMutationResponse>

// MARK: - Label

typealias AddLabelUseCase = any AsyncUseCase<AddLabelRequest, BoardResponse>
typealias EditLabelUseCase = any AsyncUseCase<EditLabelRequest, BoardResponse>
typealias DeleteLabelUseCase = any AsyncUseCase<DeleteLabelRequest, BoardResponse>

// MARK: - Markdown autosave journal (durable, disk-backed — ticket 44C9D3C2)

typealias RecordMarkdownJournalUseCase = any AsyncUseCase<RecordMarkdownJournalRequest, Void>
typealias ClearMarkdownJournalUseCase = any AsyncUseCase<ClearMarkdownJournalRequest, Void>

// MARK: - Standalone protocols
//
// Use cases whose shape doesn't fit `AsyncUseCase<Request, Response>` — no request value, or a
// return that isn't a plain `BoardResponse`.

protocol LoadCardDetailUseCase: Sendable {
    func execute(cardID: UUID) async throws -> CardDetailResponse?
}

/// Live card search over the active board (ticket 59B10FBA). Standalone (not `AsyncUseCase`) because
/// it takes a primitive `query: String`, not a `Request` struct, and returns a `Set<UUID>` — UUID is
/// an identity primitive, not a Domain concept, so no Response type is warranted.
protocol SearchCardsUseCase: Sendable {
    func execute(query: String) async throws -> Set<UUID>
}

protocol LoadImageDataUseCase: Sendable {
    /// Reads the PNG bytes for a canvas image's sidecar asset, for the canvas to decode + draw.
    func execute(assetID: UUID) async throws -> Data
}

/// Why a placed canvas image is permanently unavailable — passed to `ReportImageLoadFailureUseCase`
/// when the canvas gives up and negative-caches it (a persistent placeholder this session). Only the
/// *terminal* reasons appear here; a transient/retryable fetch failure is never reported (it retries
/// on the next redraw), so it is not a case.
enum ImageLoadFailureReason: Sendable {
    /// The sidecar asset file is absent — the board references an asset that is not on disk.
    case missingAsset
    /// The bytes loaded but are not a decodable image (a corrupt sidecar).
    case undecodableData
    /// The fetch kept failing across repeated retries — a fault that looked transient but is
    /// persistent (an unreadable sidecar: EACCES / EIO / path-is-a-directory). Promoted to terminal
    /// by the canvas after a retry cap so it stops re-fetching every redraw.
    case unreadable
}

/// Records — for diagnostics only — that a placed canvas image could not be shown and the canvas has
/// negative-cached it. Fire-and-forget: a draw-time failure is not user-awaited and logging must
/// never alter the canvas's control flow, so `execute` neither suspends nor throws. Without it the
/// reason for a permanent grey placeholder never reaches Console (ticket 37B774CD).
protocol ReportImageLoadFailureUseCase: Sendable {
    func execute(assetID: UUID, reason: ImageLoadFailureReason)
}

/// Records — for diagnostics only — that a copy-to-pasteboard write failed (`NSPasteboard.setString`
/// returned `false`). The App shell creates the AppKit pasteboard closure and propagates its `Bool`
/// result up to Presentation; this use case is the "observe the failure" half so a failed clipboard
/// write reaches Console instead of being a silent no-op (ticket 8E857E6F). Fire-and-forget like
/// `ReportImageLoadFailureUseCase`: a clipboard write is not user-awaited and logging must never alter
/// the caller's control flow, so `execute` neither suspends nor throws. `label` is a fixed operational
/// description of what was being copied (no user content).
protocol ReportPasteboardWriteFailureUseCase: Sendable {
    func execute(label: String)
}

protocol LoadBoardTemplateUseCase: Sendable {
    func execute() async throws -> BoardTemplateResponse
}

/// Reclaims orphaned canvas-image sidecar assets (files no `CanvasImage` references). Takes no
/// request and returns nothing — it is a maintenance sweep, not a board mutation, so it produces no
/// `BoardResponse`. Intended to run once at app startup as best-effort; see
/// `CanvasImageServiceProtocol.sweepOrphanedAssets`.
protocol SweepOrphanedImageAssetsUseCase: Sendable {
    func execute() async throws
}

/// Lists every pending Markdown edit left in the durable autosave journal (ticket 44C9D3C2). Takes
/// no request — it is a startup restore read, run once to re-enqueue stranded edits. Returns the
/// recovered edits (empty when the journal is clean).
protocol ListMarkdownJournalUseCase: Sendable {
    func execute() async throws -> [PendingMarkdownEditResponse]
}
