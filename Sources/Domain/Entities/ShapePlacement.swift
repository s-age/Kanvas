/// Where and how big a shape sits on a canvas — its centre `position` plus `size`. Bundling the
/// two keeps creation APIs (`ShapeService.adding`) to a single geometry argument. Mirrors
/// `StickyPlacement`.
struct ShapePlacement: Sendable, Equatable {
    var position: CanvasPosition
    var size: ShapeSize
}
