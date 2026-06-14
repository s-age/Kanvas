/// Where and how big an image sits on a canvas — its centre `position` plus `size`. Bundling the
/// two keeps creation/resize APIs (`CanvasImageService.adding` / `.resizing`) to a single geometry
/// argument. Mirrors `ShapePlacement` / `StickyPlacement`.
struct ImagePlacement: Sendable, Equatable {
    var position: CanvasPosition
    var size: ImageSize
}
