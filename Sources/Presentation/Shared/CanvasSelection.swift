import Foundation

/// The canvas's current selection. Stickies, shapes, images, and connectors are mutually
/// exclusive, so modelling the selection as a single sum type makes "two selected" unrepresentable
/// — unlike parallel optionals that only the call sites kept in sync.
///
/// `Hashable` so a multi-selection is one `Set<CanvasSelection>` — the single source of truth in
/// `BoardViewModel`, from which the lone `selection` and the raw `selectedIDs` both derive. Because
/// every id maps to exactly one kind, the synthesised (kind, id) hash never collides with a
/// different kind sharing the same id, so it is equivalent to hashing by id alone.
enum CanvasSelection: Hashable {
    case sticky(UUID)
    case shape(UUID)
    case image(UUID)
    case text(UUID)
    case connector(UUID)

    /// The selected item's id, regardless of kind (what the canvas highlights).
    var id: UUID {
        switch self {
        case .sticky(let id), .shape(let id), .image(let id), .text(let id), .connector(let id): id
        }
    }

    var stickyID: UUID? {
        if case .sticky(let id) = self { return id }
        return nil
    }

    var shapeID: UUID? {
        if case .shape(let id) = self { return id }
        return nil
    }

    var imageID: UUID? {
        if case .image(let id) = self { return id }
        return nil
    }

    var textID: UUID? {
        if case .text(let id) = self { return id }
        return nil
    }

    var connectorID: UUID? {
        if case .connector(let id) = self { return id }
        return nil
    }
}
