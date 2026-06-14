import AppKit

@MainActor
enum EllipseShape {
    static let definition = ShapeDefinition(
        kind: "ellipse", topology: .box,
        symbolName: "circle", label: "Ellipse",
        defaultWidth: 160, defaultHeight: 120,
        path: { rect in NSBezierPath(ovalIn: rect) }
    )
}
