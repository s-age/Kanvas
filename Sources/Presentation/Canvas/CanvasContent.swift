import Foundation

/// The full set of drawable Responses the canvas renders for the selected card — stickies, shapes,
/// images, free-text objects, and connectors. Bundled so `CanvasNSView.update` takes one content
/// argument instead of one per kind (which would grow past the parameter-count budget as kinds are added).
struct CanvasContent: Equatable {
    var stickies: [StickyResponse]
    var shapes: [ShapeResponse]
    var images: [ImageResponse]
    var texts: [TextResponse]
    var connectors: [ConnectorResponse]
}
