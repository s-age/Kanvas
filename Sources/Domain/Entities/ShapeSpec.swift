/// What kind of shape to create — its open visual `kind` token plus its behaviour-class
/// `topology`. Bundling the two keeps creation APIs (`ShapeService.adding`) to a single
/// shape-identity argument, mirroring how `ShapePlacement` bundles position + size.
struct ShapeSpec: Sendable, Equatable {
    /// Open visual token from the Presentation registry (e.g. "rectangle" / "triangle").
    var kind: String
    /// Behaviour class chosen by the registry at creation and persisted on the shape.
    var topology: ShapeTopology
}
