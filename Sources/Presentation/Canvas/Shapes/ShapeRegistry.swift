import AppKit

/// The catalogue + lookup + drag-payload codec for all canvas shapes. Adding a new box shape
/// requires only a new `*Shape.swift` file with a `static let definition` — no edits here.
@MainActor
enum ShapeRegistry {
    /// All shapes offered in the palette, in display order.
    static let all: [ShapeDefinition] = [
        RectangleShape.definition,
        EllipseShape.definition,
        LineShape.definition,
    ]

    /// O(1) lookup dictionary built from `all`. Used by `definition(forKind:)` which is called
    /// once per shape per redraw in the draw hot path.
    static let byKind: [String: ShapeDefinition] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.kind, $0) })

    /// Pure-Swift palette projections — no AppKit types or closures. Safe to enumerate from any
    /// SwiftUI view outside the Canvas/ carve-out.
    static let paletteItems: [ShapePaletteItem] = all.map {
        ShapePaletteItem(
            kind: $0.kind,
            symbolName: $0.symbolName,
            label: $0.label,
            defaultWidth: $0.defaultWidth,
            defaultHeight: $0.defaultHeight
        )
    }

    static func definition(forKind kind: String) -> ShapeDefinition? {
        byKind[kind]
    }

    // MARK: Palette drag payload
    static let dragPrefix = "shape:"
    static func dragPayload(forKind kind: String) -> String { dragPrefix + kind }
    /// Decodes a `"shape:<kind>"` payload to a known definition, or nil if not a shape drag / the
    /// kind is unknown.
    static func definition(forDragPayload payload: String) -> ShapeDefinition? {
        guard payload.hasPrefix(dragPrefix) else { return nil }
        return definition(forKind: String(payload.dropFirst(dragPrefix.count)))
    }

    // MARK: Default handles per topology
    //
    // The single drag loop in `CanvasNSView` iterates these for the selected shape. `requestedDrag`
    // returns *raw* world geometry only (no clamp): the box min/max preview-clamp is a Presentation
    // concern applied by the canvas, and the `minFilledSide` / `minLineLength` clamp stays in
    // `ShapeService.resizing` on commit. A genuinely new topology (its own handle layout) is added
    // by extending this switch — paired with a new `ShapeTopology` case + clamp rule in the Domain.

    static func defaultHandles(for topology: ShapeTopologyResponse) -> [ShapeHandleSpec] {
        switch topology {
        case .box:     [boxCornerHandle]
        case .segment: [segmentStartHandle, segmentEndHandle]
        }
    }

    /// Box: a single bottom-right corner handle. The opposite (top-left) corner stays fixed while
    /// the grabbed corner tracks the cursor — the raw frame the canvas then clamps to min/max.
    static let boxCornerHandle = ShapeHandleSpec(
        position: { viewFrame, _ in CGPoint(x: viewFrame.maxX, y: viewFrame.maxY) },
        requestedDrag: { toWorld, currentWorldFrame, _ in
            ShapeDragRequest(
                worldFrame: CGRect(x: currentWorldFrame.minX, y: currentWorldFrame.minY,
                                   width: toWorld.x - currentWorldFrame.minX,
                                   height: toWorld.y - currentWorldFrame.minY),
                rising: nil)
        })

    /// Segment start endpoint: the end endpoint stays fixed while the start follows the cursor.
    static let segmentStartHandle = ShapeHandleSpec(
        position: { _, endpoints in endpoints.start },
        requestedDrag: { toWorld, _, endpoints in
            ShapeDragRequest(worldFrame: boundingBox(endpoints.end, toWorld),
                             rising: rising(from: endpoints.end, to: toWorld))
        })

    /// Segment end endpoint: the start endpoint stays fixed while the end follows the cursor.
    static let segmentEndHandle = ShapeHandleSpec(
        position: { _, endpoints in endpoints.end },
        requestedDrag: { toWorld, _, endpoints in
            ShapeDragRequest(worldFrame: boundingBox(endpoints.start, toWorld),
                             rising: rising(from: endpoints.start, to: toWorld))
        })

    /// The axis-aligned box spanning two points (a segment's fixed + moved endpoints).
    private static func boundingBox(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Which diagonal a segment from `a` to `b` runs along — `true` when its right end is higher on
    /// screen (smaller y in the flipped view). Recomputes `lineRising` after an endpoint drag.
    private static func rising(from a: CGPoint, to b: CGPoint) -> Bool {
        let leftIsA = a.x <= b.x
        let left = leftIsA ? a : b
        let right = leftIsA ? b : a
        return right.y < left.y
    }
}
