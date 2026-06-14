import Foundation

struct BoardSnapshotDTO: Sendable, Codable {
    var board: BoardDTO
    var columns: [ColumnDTO]
    var cards: [CardDTO]
    var stickies: [StickyDTO]
    var shapes: [ShapeDTO]?         // Optional: snapshots predating shapes decode to nil → no shapes
    var images: [ImageDTO]?         // Optional: snapshots predating images decode to nil → no images
    var connectors: [ConnectorDTO]? // Optional: snapshots predating connectors decode to nil → none
    var texts: [TextDTO]?           // Optional: snapshots predating texts decode to nil → no texts
    var labels: [StickyLabelDTO]?   // Optional: snapshots predating the field decode to nil → no labels
    var settings: BoardSettingsDTO?  // Optional: snapshots predating settings decode to nil → defaults
}

/// Persisted free-text object (background/border-less canvas text). Mirrors `StickyDTO`'s geometry
/// fields but carries no fill / link / labels — a free-text object has only text + colour + font.
struct TextDTO: Sendable, Codable {
    var id: UUID
    var cardID: UUID
    var content: String
    var positionX: Double
    var positionY: Double
    var width: Double
    var height: Double
    var textColorHex: String?   // Optional: snapshots predating the field decode to nil → default style
    var fontSize: Double?       // Optional: snapshots predating the field decode to nil → default style
    var sortIndex: Int?         // Optional: snapshots predating the field decode to nil → array order
}

/// Persisted placement of a canvas image. The pixel bytes are **not** here — they live in a
/// sidecar asset file keyed by `assetID` (see `FileImageAssetStore`); this DTO only references it.
struct ImageDTO: Sendable, Codable {
    var id: UUID
    var cardID: UUID
    var assetID: UUID               // Sidecar pixel-asset reference: assets/<assetID>.png
    var positionX: Double
    var positionY: Double
    var width: Double
    var height: Double
    var aspectRatio: Double?        // Optional: snapshots predating the field fall back to width/height
    var sortIndex: Int?             // Optional: snapshots predating the field decode to nil → array order

    /// The Swift property is `assetID` (consistent with the entity / Presentation), but the
    /// **persisted JSON key stays `imageID`** — that was the key the first shipped builds wrote,
    /// and renaming it would make every already-saved snapshot fail to decode (it did, once:
    /// "Board data file is corrupted"). Keep the on-disk key stable; the rename lives only in code.
    enum CodingKeys: String, CodingKey {
        case id
        case cardID
        case assetID = "imageID"
        case positionX
        case positionY
        case width
        case height
        case aspectRatio
        case sortIndex
    }
}

struct ConnectorDTO: Sendable, Codable {
    var id: UUID
    var cardID: UUID
    var sourceStickyID: UUID
    var sourceEdge: String          // CanvasEdge raw value: "top" | "bottom" | "left" | "right"
    var targetStickyID: UUID
    var targetEdge: String
    var cap: String?                // ConnectorEndpointCap raw value; absent ⇒ default style
    var routing: String?            // ConnectorRouting raw value; absent ⇒ default style
    var strokeColorHex: String?     // Optional: absent ⇒ default style
    var strokeWidth: Double?        // Optional: absent ⇒ default style
    var waypointOffsetX: Double? = nil // Optional: waypoint (midpoint deformation) X; absent ⇒ no waypoint
    var waypointOffsetY: Double? = nil // Optional: waypoint (midpoint deformation) Y; absent ⇒ no waypoint
}

struct StickyLabelDTO: Sendable, Codable {
    var id: UUID
    var name: String
    var colorHex: String
}

struct BoardDTO: Sendable, Codable {
    var id: UUID
    var title: String
}

struct ColumnDTO: Sendable, Codable {
    var id: UUID
    var boardID: UUID
    var title: String
    var sortIndex: Int
    var isCompletionColumn: Bool?   // Optional: snapshots predating the field decode to nil → false
    var headerColorHex: String?     // Optional: per-column header background; nil ⇒ board-wide fallback
    var headerTextColorHex: String? // Optional: per-column header text colour; nil ⇒ board text colour
    var bodyColorHex: String?       // Optional: per-column body (card-stack area) background; nil ⇒ default
    var headerBorderColorHex: String? = nil // Optional: per-column header border; nil ⇒ no border
    var bodyBorderColorHex: String? = nil   // Optional: per-column body border; nil ⇒ no border
    var indicatorColorHex: String? = nil    // Optional: per-column status-dot colour; nil ⇒ neutral default
}

struct CardDTO: Sendable, Codable {
    var id: UUID
    var columnID: UUID
    var title: String
    var markdownContent: String
    /// Legacy field — a card's status is now derived from its column, not stored. Kept Optional so
    /// old snapshots (which carry a `status` string) still decode; new snapshots omit it and the
    /// mapper ignores any value present.
    var status: String?
    var schedule: CardScheduleDTO?
    var labels: [CardLabelDTO]
    var assignee: String?       // Optional: absent in snapshots predating the field
    var prURL: String?          // Optional: absent in snapshots predating the field → nil (no PR linked)
    var completedAt: Date?
    var createdAt: Date?        // Optional: snapshots predating the field decode to nil → .distantPast
    var sortIndex: Int
}

struct CardScheduleDTO: Sendable, Codable {
    var kind: String        // "deadline" | "period"
    var date: Date?         // for deadline
    var startDate: Date?    // for period
    var endDate: Date?      // for period
}

struct CardLabelDTO: Sendable, Codable {
    var id: UUID
    var name: String
    var colorHex: String
}

struct StickyDTO: Sendable, Codable {
    var id: UUID
    var cardID: UUID
    var linkedCardID: UUID?
    var content: String
    var positionX: Double
    var positionY: Double
    var width: Double
    var height: Double
    var textColorHex: String?   // Optional: snapshots predating the field decode to nil → default style
    var fontSize: Double?       // Optional: snapshots predating the field decode to nil → default style
    var fillColorHex: String?   // Optional: per-sticky fill; nil → inherit board free/task default
    var sortIndex: Int?         // Optional: snapshots predating the field decode to nil → array order
    var labelIDs: [UUID]?       // Optional: snapshots predating the field decode to nil → no labels
}

struct ShapeDTO: Sendable, Codable {
    var id: UUID
    var cardID: UUID
    var kind: String                // open visual token: "rectangle" | "ellipse" | "line" | …
    /// Behaviour-class raw value ("box" | "segment"). New optional field (no shape DTO carried a
    /// behaviour-class key before this change), default-nil: snapshots predating it decode to nil →
    /// inferred from `kind` in the mapper ("line" → segment, else box). Maps to entity `topology`.
    var topology: String? = nil
    var positionX: Double
    var positionY: Double
    var width: Double
    var height: Double
    var strokeColorHex: String?     // Optional: snapshots predating the field decode to nil → default style
    var strokeWidth: Double?        // Optional: snapshots predating the field decode to nil → default style
    var fillColorHex: String?       // nil ⇒ no literal colour; pair with `hasFill` to tell "no fill" apart
    /// Explicit "has a fill" flag so a stroke-only shape (`fillColorHex == nil`) is distinguishable
    /// from an old snapshot missing the field. Optional for forward compat; absent ⇒ infer from
    /// `fillColorHex != nil`.
    var hasFill: Bool?
    var lineRising: Bool?           // Line only; absent ⇒ false (top-left→bottom-right)
    var sortIndex: Int?             // Optional: snapshots predating the field decode to nil → array order
}
