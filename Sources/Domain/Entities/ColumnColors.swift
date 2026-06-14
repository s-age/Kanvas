/// The per-column colour overrides (all hex; `nil` ⇒ fall back to the board/default). Bundled into
/// one value so column-appearance APIs stay within the parameter-count budget.
struct ColumnColors: Sendable, Equatable {
    var headerColorHex: String?        // header background
    var headerTextColorHex: String?    // header text
    var bodyColorHex: String?          // body (card-stack area) background
    var headerBorderColorHex: String?  // header border
    var bodyBorderColorHex: String?    // body border
    var indicatorColorHex: String?     // status-indicator dot (per card head)

    init(
        headerColorHex: String? = nil,
        headerTextColorHex: String? = nil,
        bodyColorHex: String? = nil,
        headerBorderColorHex: String? = nil,
        bodyBorderColorHex: String? = nil,
        indicatorColorHex: String? = nil
    ) {
        self.headerColorHex = headerColorHex
        self.headerTextColorHex = headerTextColorHex
        self.bodyColorHex = bodyColorHex
        self.headerBorderColorHex = headerBorderColorHex
        self.bodyBorderColorHex = bodyBorderColorHex
        self.indicatorColorHex = indicatorColorHex
    }
}
