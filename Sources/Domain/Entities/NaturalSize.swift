/// Source pixel dimensions of an image as supplied by the importer (drop / paste). Unlike
/// `ImageSize` (the clamped on-canvas box), this is the *natural* size used only to fit an initial
/// on-canvas size and derive the source aspect ratio — so it is **not** clamped. Bundling the two
/// dimensions keeps `CanvasImageService.add` within the parameter-count budget (the pair always
/// travels together).
struct NaturalSize: Sendable, Equatable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
