struct BoardTabSettings: Sendable, Equatable {
    var cardSortPolicy: CardSortPolicy
    var autoCompleteOnMove: Bool
    /// Per-board **card background** colour. `nil` ⇒ default card background.
    var cardBackgroundColorHex: String?
    /// Per-board **card text** colour. `nil` ⇒ the system default card text colour.
    var cardTextColorHex: String?
    /// Per-board **card border** colour. `nil` ⇒ no border.
    var cardBorderColorHex: String?
    /// Per-board text colour for the Kanban board. `nil` falls back to the shared
    /// `GlobalSettings.textColorHex`, then the default — so a board can override its own text
    /// colour without affecting the canvas / Markdown editor.
    var textColorHex: String?
    var newCardPosition: NewCardPosition

    init(
        cardSortPolicy: CardSortPolicy = .manual,
        autoCompleteOnMove: Bool = true,
        cardBackgroundColorHex: String? = nil,
        cardTextColorHex: String? = nil,
        cardBorderColorHex: String? = nil,
        textColorHex: String? = nil,
        newCardPosition: NewCardPosition = .bottom
    ) {
        self.cardSortPolicy = cardSortPolicy
        self.autoCompleteOnMove = autoCompleteOnMove
        self.cardBackgroundColorHex = cardBackgroundColorHex
        self.cardTextColorHex = cardTextColorHex
        self.cardBorderColorHex = cardBorderColorHex
        self.textColorHex = textColorHex
        self.newCardPosition = newCardPosition
    }

    static let `default` = BoardTabSettings()
}
