import Foundation

/// Creation input for a new card, bundled so `CardService.adding` stays within the
/// parameter-count budget (the `*Placement` pattern). `id` is caller-supplied so the UseCase can
/// report the created card's identity in its Response without diffing pre/post state.
struct CardSeed: Sendable, Equatable {
    let id: Card.ID
    let title: String
    /// Initial Markdown detail, applied in the same mutation as the card itself; `nil` ⇒ empty.
    let markdownContent: String?

    init(id: Card.ID = UUID(), title: String, markdownContent: String? = nil) {
        self.id = id
        self.title = title
        self.markdownContent = markdownContent
    }
}
