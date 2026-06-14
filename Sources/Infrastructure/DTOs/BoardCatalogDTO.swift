import Foundation

/// The persisted index over every board. Lives at `Kanvas/catalog.json`, alongside the
/// per-board snapshots under `Kanvas/boards/<id>.json`. The catalog is the authoritative
/// source for the board picker (id + title + display order) and for which board is active,
/// so the board switcher never needs to decode every snapshot just to list names.
struct BoardCatalogDTO: Sendable, Codable {
    /// The board currently shown. `nil` only transiently before the first board is inserted.
    var activeBoardID: UUID?
    /// All boards in display order.
    var boards: [BoardRefDTO]
}

/// A lightweight board reference for the catalog — identity plus the picker-facing title.
struct BoardRefDTO: Sendable, Codable {
    var id: UUID
    var title: String
}
