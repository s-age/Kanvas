import Foundation

/// Identifies a canvas image's sidecar pixel asset plus its intrinsic shape. Bundles the two
/// source facts that `CanvasImageService.adding` needs alongside geometry, keeping that method to
/// a single asset argument (mirrors how `ImagePlacement` bundles position + size).
///
/// `aspectRatio` is the source's natural width ÷ height — kept distinct from the on-canvas
/// `ImageSize` (which may be clamped/fitted), so resizing can always restore the true ratio.
struct ImageAssetRef: Sendable, Equatable {
    let assetID: UUID
    let aspectRatio: Double
}
