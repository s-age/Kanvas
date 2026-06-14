import Foundation

struct BoardSettingsDTO: Sendable, Codable {
    var global: GlobalSettingsDTO?
    var board: BoardTabSettingsDTO?
    var canvas: CanvasSettingsDTO?
    var markdown: MarkdownSettingsDTO?
}

struct GlobalSettingsDTO: Sendable, Codable {
    var backgroundColorHex: String?
    var textColorHex: String?
    /// The Global colour palette. Optional so a snapshot predating the field decodes to nil →
    /// seeded with `PaletteColor.defaultPalette` in the mapper. A present-but-empty array means
    /// the user cleared the palette and is preserved as empty (distinct from nil = predates field).
    var colorPalette: [PaletteColorDTO]?
}

struct PaletteColorDTO: Sendable, Codable {
    var id: UUID?
    var colorHex: String?
    var label: String?
}

struct BoardTabSettingsDTO: Sendable, Codable {
    var cardSortPolicy: String?
    var autoCompleteOnMove: Bool?
    var cardBackgroundColorHex: String?
    var cardTextColorHex: String?
    var cardBorderColorHex: String? = nil // Optional: absent in snapshots predating the field
    var textColorHex: String?
    var newCardPosition: String?
}

struct CanvasSettingsDTO: Sendable, Codable {
    /// The palette's drag-to-create presets. Optional so snapshots predating the field decode to
    /// nil → seeded with the default S/M/L set in the mapper. Replaces the former
    /// `defaultStickyWidth`/`defaultStickyHeight` (those keys are simply ignored if still present).
    var stickyPresets: [StickyPresetDTO]?
    var defaultFontSize: Double?
    var defaultTextColorHex: String?
    var freeStickyColorHex: String?
    var taskStickyColorHex: String?
    var initialZoomScale: Double?
    var gridSnapInterval: Double?
}

struct StickyPresetDTO: Sendable, Codable {
    var id: UUID?
    var label: String?
    var colorHex: String?
    var width: Double?
    var height: Double?
}

struct MarkdownSettingsDTO: Sendable, Codable {
    var baseFontSize: Double?
    var headingSizes: [Double]?
    var codeColorHex: String?
    var quoteColorHex: String?
    var useMonospacedFont: Bool?
    // Block-decoration fields. Optional so snapshots predating these fields decode cleanly.
    var codeBlockBackgroundColorHex: String?
    var quoteBorderColorHex: String?
    var quoteBorderWidth: Double?
    var linkColorHex: String?
    // Paragraph-styling fields. Optional so snapshots predating these fields decode cleanly.
    var editorBackgroundColorHex: String?
    var listIndentExtra: Double?
    var listItemSpacing: Double?
    var lineSpacing: Double?
    /// Per-token-kind code-block syntax-highlight colour overrides (token-kind key → hex). Optional
    /// so snapshots predating the field decode cleanly; absent → empty map in the mapper.
    var syntaxColorOverrides: [String: String]?
}
