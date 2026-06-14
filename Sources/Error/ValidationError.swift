import Foundation

enum ValidationError: LocalizedError, Equatable, Sendable {
    case emptyTitle
    case titleTooLong(max: Int)
    case contentTooLong(max: Int)
    case imageDataTooLarge(maxBytes: Int)
    case invalidDateRange
    case emptyLabelName
    case invalidColorHex
    case invalidShapeKind
    case invalidShapeTopology
    case invalidConnectorEdge
    case invalidConnectorCap
    case invalidConnectorRouting
    case connectorSelfLoop
    case invalidConnectorWaypoint
    case emptyImageData
    case fontSizeOutOfRange(min: Double, max: Double)
    case strokeWidthOutOfRange(min: Double, max: Double)
    case nonFiniteCoordinate

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Title must not be empty."
        case .titleTooLong(let max): "Title must be \(max) characters or fewer."
        case .contentTooLong(let max): "Content must be \(max) characters or fewer."
        case .imageDataTooLarge(let maxBytes):
            "Image must be \(maxBytes / (1024 * 1024)) MiB (\(maxBytes) bytes) or smaller."
        case .invalidDateRange: "End date must be after start date."
        case .emptyLabelName: "Label name must not be empty."
        case .invalidColorHex: "Colour must be a 6-digit RGB hex."
        case .invalidShapeKind: "Shape kind must not be empty."
        case .invalidShapeTopology: "Shape topology must be box or segment."
        case .invalidConnectorEdge: "Connector edge must be top, bottom, left, or right."
        case .invalidConnectorCap: "Connector cap must be line or arrow."
        case .invalidConnectorRouting: "Connector routing must be straight, elbow, or curve."
        case .connectorSelfLoop: "A connector cannot link a sticky to itself."
        case .invalidConnectorWaypoint: "A connector waypoint must specify both axes, or neither."
        case .emptyImageData: "Image data must not be empty."
        case .fontSizeOutOfRange(let min, let max):
            "Font size must be between \(min.formatted(.number)) and \(max.formatted(.number))."
        case .strokeWidthOutOfRange(let min, let max):
            "Stroke width must be between \(min.formatted(.number)) and \(max.formatted(.number))."
        case .nonFiniteCoordinate: "Coordinates must be finite numbers."
        }
    }
}
