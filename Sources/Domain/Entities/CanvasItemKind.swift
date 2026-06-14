import Foundation

/// Which canvas collection a given id belongs to. The closed set of element kinds that share a
/// card's canvas — used to route a group operation (move / delete over a multi-selection) to the
/// right per-kind transform without the caller having to know each id's type. Connectors are a
/// member here (so group-delete can route them) even though they carry no geometry and so never
/// take part in a move.
enum CanvasItemKind: Equatable, Sendable {
    case sticky
    case shape
    case image
    case text
    case connector
}
