import AppKit

@MainActor
enum LineShape {
    static let definition = ShapeDefinition(
        kind: "line", topology: .segment,
        symbolName: "line.diagonal", label: "Line",
        defaultWidth: 160, defaultHeight: 120,
        path: { _ in NSBezierPath() }   // segment never uses path
    )
}
