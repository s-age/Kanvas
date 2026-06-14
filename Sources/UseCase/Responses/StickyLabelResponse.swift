import Foundation

/// A shared sticky-label definition exposed to Presentation. The full registry is carried on
/// `BoardResponse.labels`; the resolved labels tagged on a sticky are on `StickyResponse.labels`.
struct StickyLabelResponse: Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let colorHex: String
}
