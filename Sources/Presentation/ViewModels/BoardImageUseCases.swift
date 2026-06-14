import Foundation

/// The canvas-image use cases, bundled so `BoardViewModel` injects one dependency instead of seven
/// — keeping its initializer and body within the length budgets. Consumed by the
/// `BoardViewModel+ImageActions` extension.
struct BoardImageUseCases: Sendable {
    let add: AddImageUseCase
    let move: MoveImageUseCase
    let resize: ResizeImageUseCase
    let delete: DeleteImageUseCase
    let bringToFront: BringImageToFrontUseCase
    let sendToBack: SendImageToBackUseCase
    /// Saves dropped image bytes as a sidecar asset and returns its id, without placing a
    /// `CanvasImage` — the Markdown editor's inline-image import path (`addMarkdownImage`).
    let saveAsset: SaveImageAssetUseCase
    /// Removes a Markdown inline image reference from a card and reclaims its bytes when no board
    /// references the asset any more — the gallery delete button's path (`deleteMarkdownImage`).
    let deleteMarkdownImage: DeleteMarkdownImageUseCase
    let loadData: any LoadImageDataUseCase
    /// One-shot startup maintenance: reclaims sidecar assets no `CanvasImage` references.
    let sweepOrphans: any SweepOrphanedImageAssetsUseCase
    /// Fire-and-forget diagnostic: the canvas reports a placed image it permanently could not show
    /// (missing/undecodable sidecar) so the grey placeholder's reason reaches Console (ticket 37B774CD).
    let reportLoadFailure: any ReportImageLoadFailureUseCase
}
