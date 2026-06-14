import Foundation

/// Persisted shape of the app-level Default template (`template.json`). All fields optional so a
/// file predating any field still decodes; the mapper coerces missing values to defaults.
struct BoardTemplateDTO: Sendable, Codable {
    var settings: BoardSettingsDTO?
    var columns: [TemplateColumnDTO]?
}

struct TemplateColumnDTO: Sendable, Codable {
    var id: UUID
    var title: String
    var sortIndex: Int
    var isCompletionColumn: Bool?
    var headerColorHex: String?
    var headerTextColorHex: String?
    var bodyColorHex: String?
    var headerBorderColorHex: String? = nil // Optional: absent in templates predating the field
    var bodyBorderColorHex: String? = nil   // Optional: absent in templates predating the field
    var indicatorColorHex: String? = nil    // Optional: absent in templates predating the field
}
