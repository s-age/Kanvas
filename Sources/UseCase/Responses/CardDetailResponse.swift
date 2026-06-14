import Foundation

struct CardDetailResponse: Sendable, Equatable {
    let id: UUID
    let title: String
    let markdownContent: String
    /// Derived from the card's column (`BoardState.status(forColumn:)`), not stored on the card.
    let status: CardStatusResponse
    /// The title of the column the card sits in — the human-readable status, shown in the metadata
    /// editor's status chip. Follows column renames for free since it is read live from the column.
    let columnTitle: String
    let schedule: ScheduleResponse?
    let labels: [LabelResponse]
    let assignee: String?
    let prURL: String?
    let completedAt: Date?
    let stickies: [StickyResponse]
    let shapes: [ShapeResponse]
    let images: [ImageResponse]
    let texts: [TextResponse]
    let connectors: [ConnectorResponse]
}

/// A free-text canvas object exposed to Presentation. Background/border-less text positioned by its
/// centre; text wraps to `width` and is clipped at `height`. Carries the resize + font-size bounds
/// from the domain so Presentation clamps previews against the same authoritative values it commits.
struct TextResponse: Sendable, Equatable, Identifiable {
    let id: UUID
    let content: String
    let positionX: Double
    let positionY: Double
    let width: Double
    let height: Double
    let minWidth: Double
    let minHeight: Double
    let maxWidth: Double
    let maxHeight: Double
    let textColorHex: String
    let fontSize: Double
    let minFontSize: Double
    let maxFontSize: Double
    let sortIndex: Int
}

enum ScheduleResponse: Sendable, Equatable {
    case deadline(Date)
    case period(start: Date, end: Date)
}

struct LabelResponse: Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let colorHex: String
}

struct StickyResponse: Sendable, Equatable, Identifiable {
    let id: UUID
    let content: String
    let isTask: Bool
    let linkedCardTitle: String?
    let positionX: Double
    let positionY: Double
    let width: Double
    let height: Double
    /// Resize bounds carried from the domain (`StickySize`) so Presentation clamps the live
    /// resize preview against the same authoritative values it will be committed against —
    /// no duplicated magic numbers, no preview-vs-commit snap-back.
    let minWidth: Double
    let minHeight: Double
    let maxWidth: Double
    let maxHeight: Double
    let textColorHex: String
    let fontSize: Double
    /// Per-sticky background **fill** ("RRGGBB"), or `nil` to inherit the board's free/task
    /// default. Distinct from `textColorHex`. Set from the palette preset's colour at creation;
    /// the canvas tint resolver prefers it.
    let fillColorHex: String?
    let sortIndex: Int
    /// Labels tagged on this sticky, resolved from the registry in registry order. Drawn as
    /// coloured pills along the sticky's bottom edge.
    let labels: [StickyLabelResponse]
}

/// Behaviour-class mirror of the domain `ShapeTopology`. Presentation switches on this
/// (handles / hit-testing / draw branch / toolbar) instead of importing the domain enum.
enum ShapeTopologyResponse: String, Sendable, Equatable {
    case box
    case segment

    init(_ topology: ShapeTopology) {
        switch topology {
        case .box: self = .box
        case .segment: self = .segment
        }
    }
}

struct ShapeResponse: Sendable, Equatable, Identifiable {
    let id: UUID
    /// Open visual token — the Presentation registry maps it to a path/symbol/label. Presentation
    /// must tolerate an unknown token (a shape whose definition file was removed): fall back to a
    /// box outline for drawing but still honour `topology` for hit-testing/handles.
    let kind: String
    /// Behaviour class — drives handles, hit-testing, the draw branch, and the toolbar's fill row.
    let topology: ShapeTopologyResponse
    let positionX: Double
    let positionY: Double
    let width: Double
    let height: Double
    /// Resize bounds carried from the domain (`ShapeSize`) so Presentation clamps the live resize
    /// preview against the same authoritative values it commits against (no snap-back).
    let minWidth: Double
    let minHeight: Double
    let maxWidth: Double
    let maxHeight: Double
    let strokeColorHex: String
    let strokeWidth: Double
    /// Stroke-width bounds carried from the domain (`CanvasShapeStyle`) so the toolbar stepper
    /// clamps against the same authoritative range — no duplicated literals in Presentation.
    let minStrokeWidth: Double
    let maxStrokeWidth: Double
    /// `nil` means **no fill** (stroke-only); any value is a literal "RRGGBB" fill colour.
    let fillColorHex: String?
    /// Segment only: which diagonal of the box the segment runs along — lets the canvas place the
    /// two endpoint handles and draw the segment. `false` = top-left→bottom-right, `true` =
    /// bottom-left→top-right. Ignored for box shapes.
    let lineRising: Bool
    let sortIndex: Int
}

/// A bitmap image placed on a card's canvas, exposed to Presentation. Carries the placement
/// geometry plus `assetID` — the canvas fetches the pixels lazily by that id (via
/// `LoadImageDataUseCaseImpl`) and caches the decoded image, so the Response stays light (no bytes).
struct ImageResponse: Sendable, Equatable, Identifiable {
    /// The canvas item's id (target of move/resize/delete/z-order actions).
    let id: UUID
    /// The sidecar pixel asset's id — the cache key + argument to `LoadImageDataUseCaseImpl`.
    let assetID: UUID
    let positionX: Double
    let positionY: Double
    let width: Double
    let height: Double
    /// Resize bounds carried from the domain (`ImageSize`) so Presentation clamps the live resize
    /// preview against the same authoritative values it commits against (no snap-back).
    let minWidth: Double
    let minHeight: Double
    let maxWidth: Double
    let maxHeight: Double
    /// Source width ÷ height — lets the canvas lock the resize preview to the image's true shape.
    let aspectRatio: Double
    let sortIndex: Int
}

/// Connector edge / cap / routing exposed to Presentation. Mirror the domain raw values;
/// Presentation switches on these instead of importing the domain enums (the layer boundary
/// forbids it).
///
/// Read-only on purpose: each carries `init(_:)` (Domain→Response) but no `toDomain` — the write
/// path (`AddConnectorRequest` etc.) still receives `String` raw values from Presentation and
/// resolves them with `CanvasEdge(rawValue:)`, so the reverse direction would be unreachable
/// vocabulary here (mirror enums on the Request side is a separate ticket).
enum CanvasEdgeResponse: String, Sendable, Equatable {
    case top
    case bottom
    case left
    case right

    init(_ edge: CanvasEdge) {
        switch edge {
        case .top: self = .top
        case .bottom: self = .bottom
        case .left: self = .left
        case .right: self = .right
        }
    }
}

enum ConnectorCapResponse: String, Sendable, Equatable {
    case line
    case arrow

    init(_ cap: ConnectorEndpointCap) {
        switch cap {
        case .line: self = .line
        case .arrow: self = .arrow
        }
    }
}

enum ConnectorRoutingResponse: String, Sendable, Equatable {
    case straight
    case elbow
    case curve

    init(_ routing: ConnectorRouting) {
        switch routing {
        case .straight: self = .straight
        case .elbow: self = .elbow
        case .curve: self = .curve
        }
    }
}

/// A directed sticky→sticky link exposed to Presentation. Carries the two endpoints' sticky ids +
/// edges so the canvas can resolve each endpoint to its sticky's live edge midpoint, plus the
/// style. Stroke-width bounds are carried from the domain (`ConnectorStyle`) so the toolbar stepper
/// clamps against the same authoritative range.
struct ConnectorResponse: Sendable, Equatable, Identifiable {
    let id: UUID
    let sourceStickyID: UUID
    let sourceEdge: CanvasEdgeResponse
    let targetStickyID: UUID
    let targetEdge: CanvasEdgeResponse
    let cap: ConnectorCapResponse
    let routing: ConnectorRoutingResponse
    /// `nil` = unset stroke → Presentation draws it adaptively (`#333`/`#ddd` by live background);
    /// a non-nil hex is explicit and rendered verbatim. Mirrors `ConnectorStyle.strokeColorHex`.
    let strokeColorHex: String?
    let strokeWidth: Double
    let minStrokeWidth: Double
    let maxStrokeWidth: Double
    /// The connector's waypoint (midpoint deformation) offset, or `nil` for the automatic route.
    /// Carried as two raw `Double`s so Presentation never imports the domain `CanvasOffset`; both are
    /// non-nil together or both nil (mirrors `Connector.waypointOffset`). Used by the canvas to draw
    /// and drag the central deformation handle (elbow/curve only — ignored for straight).
    let waypointOffsetX: Double?
    let waypointOffsetY: Double?
}
