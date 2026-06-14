import AppKit

@MainActor
enum RectangleShape {
    static let definition = ShapeDefinition(
        kind: "rectangle", topology: .box,
        symbolName: "rectangle", label: "Rectangle",
        defaultWidth: 160, defaultHeight: 120,
        path: { rect in NSBezierPath(rect: rect) }
    )
}
