import Foundation

/// A bitmap image placed on a card's canvas. Mirrors `Sticky`/`CanvasShape` as a movable,
/// resizable canvas object, but carries no text or styling — only a reference to its pixels.
///
/// The pixel bytes are **not** stored here (or in the board snapshot): they live as a sidecar
/// file keyed by `imageID`, written/read through the image-asset store. This entity holds only
/// the asset reference plus geometry, so the board JSON stays small and a save never rewrites the
/// image. Shares the canvas `sortIndex` z-order space with stickies and shapes (see
/// `BoardState.nextFrontCanvasIndex`), so an image can sit in front of or behind either.
struct CanvasImage: Sendable, Identifiable, Equatable {
    let id: UUID
    var cardID: Card.ID
    /// Reference to the sidecar pixel asset (`assets/<assetID>.png`). Named `assetID` (not
    /// `imageID`) to contrast clearly with the canvas item's own `id`: `id` = this placement,
    /// `assetID` = the pixels. Distinct from `id` so the asset's lifecycle is decoupled from the
    /// item's (and the same bytes could in principle be shared by two items).
    let assetID: UUID
    var position: CanvasPosition
    var size: ImageSize
    /// The source image's natural width ÷ height. Held so resizing can preserve the ratio (the
    /// canvas only feeds back a new width; the height follows). Always > 0.
    let aspectRatio: Double
    /// Stacking order within a card's canvas — shared with stickies/shapes; higher draws in front.
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        cardID: Card.ID,
        assetID: UUID,
        position: CanvasPosition,
        size: ImageSize,
        aspectRatio: Double,
        sortIndex: Int
    ) {
        self.id = id
        self.cardID = cardID
        self.assetID = assetID
        self.position = position
        self.size = size
        // Guard against a zero/negative ratio (degenerate or hand-edited JSON) so resize math
        // never divides by zero; fall back to square.
        self.aspectRatio = aspectRatio > 0 ? aspectRatio : 1
        self.sortIndex = sortIndex
    }
}
