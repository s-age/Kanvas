import Foundation

/// A column in the app-level Default template. Like `Column` but board-agnostic (no `boardID`) —
/// it is a blueprint instantiated into a fresh `Column` for each new board.
struct TemplateColumn: Sendable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var sortIndex: Int
    var isCompletionColumn: Bool
    var headerColorHex: String?
    var headerTextColorHex: String?
    var bodyColorHex: String?
    var headerBorderColorHex: String?
    var bodyBorderColorHex: String?
    var indicatorColorHex: String?

    init(
        id: UUID = UUID(),
        title: String,
        sortIndex: Int,
        isCompletionColumn: Bool = false,
        headerColorHex: String? = nil,
        headerTextColorHex: String? = nil,
        bodyColorHex: String? = nil,
        headerBorderColorHex: String? = nil,
        bodyBorderColorHex: String? = nil,
        indicatorColorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sortIndex = sortIndex
        self.isCompletionColumn = isCompletionColumn
        self.headerColorHex = headerColorHex
        self.headerTextColorHex = headerTextColorHex
        self.bodyColorHex = bodyColorHex
        self.headerBorderColorHex = headerBorderColorHex
        self.bodyBorderColorHex = bodyBorderColorHex
        self.indicatorColorHex = indicatorColorHex
    }
}

/// The app-level Default board template: the settings and column blueprint copied into every
/// newly-created board. Editing it never touches existing boards — it only shapes future ones.
struct BoardTemplate: Sendable, Equatable {
    var settings: BoardSettings
    var columns: [TemplateColumn]

    init(settings: BoardSettings = .default, columns: [TemplateColumn]) {
        self.settings = settings
        self.columns = columns
    }

    /// The built-in fallback used before any template is persisted: the historical
    /// To Do / In Progress / Done seed with default settings. The three columns seed an explicit
    /// indicator-dot colour (blue / orange / green) so a freshly-minted board preserves the historical
    /// status-dot look; an added column (no seed) falls back to the neutral default at render time.
    static let `default` = BoardTemplate(
        settings: .default,
        columns: [
            TemplateColumn(title: "To Do", sortIndex: 0, isCompletionColumn: false,
                           indicatorColorHex: "007AFF"),
            TemplateColumn(title: "In Progress", sortIndex: 1, isCompletionColumn: false,
                           indicatorColorHex: "FF9500"),
            TemplateColumn(title: "Done", sortIndex: 2, isCompletionColumn: true,
                           indicatorColorHex: "34C759"),
        ]
    )
}
