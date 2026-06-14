import Foundation

/// The Default template read-model surfaced to Presentation: the settings + column blueprint
/// copied into every newly-created board.
struct BoardTemplateResponse: Sendable, Equatable {
    var settings: BoardSettingsResponse
    var columns: [TemplateColumnResponse]
}

struct TemplateColumnResponse: Sendable, Equatable, Identifiable {
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
}
