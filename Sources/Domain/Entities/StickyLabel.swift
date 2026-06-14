import Foundation

/// An app-wide, shared label definition that stickies reference by `id` (many-to-many).
/// The registry of all labels lives on `BoardState.labels`; a sticky stores only the ids it
/// is tagged with (`Sticky.labelIDs`). Distinct from the Kanban `CardLabel` system.
struct StickyLabel: Sendable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}
