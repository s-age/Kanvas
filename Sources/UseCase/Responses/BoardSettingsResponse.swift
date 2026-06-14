import Foundation

struct BoardSettingsResponse: Sendable, Equatable {
    var global: GlobalSettingsResponse
    var board: BoardTabSettingsResponse
    var canvas: CanvasSettingsResponse
    var markdown: MarkdownSettingsResponse
}

struct GlobalSettingsResponse: Sendable, Equatable {
    var backgroundColorHex: String?
    var textColorHex: String?
    /// The Global colour palette (colour + optional label), in display order.
    var colorPalette: [PaletteColorResponse]
}

struct PaletteColorResponse: Sendable, Equatable, Identifiable {
    let id: UUID
    var colorHex: String
    var label: String
}

struct BoardTabSettingsResponse: Sendable, Equatable {
    var cardSortPolicy: CardSortPolicyResponse
    var autoCompleteOnMove: Bool
    var cardBackgroundColorHex: String?
    var cardTextColorHex: String?
    /// Per-board card border colour (hex); `nil` ⇒ no border.
    var cardBorderColorHex: String?
    var textColorHex: String?
    var newCardPosition: NewCardPositionResponse
}

/// The board's card-sort policy exposed to Presentation. Mirrors the domain `CardSortPolicy` raw
/// values so Presentation drives its picker from the case set directly — the `init(_:)`/`toDomain`
/// switches cross the boundary exhaustively, with no `rawValue` round-trip and no silent
/// `?? .default` fallback. The display order rule (`CardSortPolicy.ordered`) stays in the domain.
enum CardSortPolicyResponse: String, Sendable, Equatable, CaseIterable {
    case manual
    case titleAscending
    case createdNewest
    case createdOldest

    init(_ policy: CardSortPolicy) {
        switch policy {
        case .manual: self = .manual
        case .titleAscending: self = .titleAscending
        case .createdNewest: self = .createdNewest
        case .createdOldest: self = .createdOldest
        }
    }

    var toDomain: CardSortPolicy {
        switch self {
        case .manual: .manual
        case .titleAscending: .titleAscending
        case .createdNewest: .createdNewest
        case .createdOldest: .createdOldest
        }
    }
}

/// Where a newly added card lands in its column, exposed to Presentation. Mirrors the domain
/// `NewCardPosition` raw values; the `init(_:)`/`toDomain` switches cross the boundary exhaustively.
enum NewCardPositionResponse: String, Sendable, Equatable, CaseIterable {
    case top
    case bottom

    init(_ position: NewCardPosition) {
        switch position {
        case .top: self = .top
        case .bottom: self = .bottom
        }
    }

    var toDomain: NewCardPosition {
        switch self {
        case .top: .top
        case .bottom: .bottom
        }
    }
}

struct CanvasSettingsResponse: Sendable, Equatable {
    /// The palette's drag-to-create presets (label / colour / absolute size), in display order.
    var stickyPresets: [StickyPresetResponse]
    var defaultFontSize: Double
    var defaultTextColorHex: String
    var freeStickyColorHex: String?
    var taskStickyColorHex: String?
    var initialZoomScale: Double
    var gridSnapInterval: Double
}

struct StickyPresetResponse: Sendable, Equatable, Identifiable {
    let id: UUID
    var label: String
    var colorHex: String
    var width: Double
    var height: Double
}

struct MarkdownSettingsResponse: Sendable, Equatable {
    var baseFontSize: Double
    var headingSizes: [Double]
    var codeColorHex: String?
    var quoteColorHex: String?
    var useMonospacedFont: Bool
    var codeBlockBackgroundColorHex: String?
    var quoteBorderColorHex: String?
    var quoteBorderWidth: Double
    var linkColorHex: String?
    var editorBackgroundColorHex: String?
    var listIndentExtra: Double
    var listItemSpacing: Double
    var lineSpacing: Double
    /// Per-token-kind code-block syntax-highlight colour overrides (token-kind key → hex). Empty =
    /// entirely built-in palette. The key vocabulary is Presentation-owned (`MarkdownAppearance`).
    var syntaxColorOverrides: [String: String]
}

// MARK: - Domain entity → Response mapping + Domain-derived defaults
//
// These map the Domain settings entities to their Responses, and expose `.default` derived from
// the entity's own `.default`. Presentation cannot import `Domain`, so it reads these Responses for
// reset-to-defaults and "still at defaults" checks — keeping every default literal defined exactly
// once, on the Domain entity, with no hand-copied Presentation mirror to drift.

extension StickyPresetResponse {
    init(_ preset: StickyPreset) {
        self.init(id: preset.id, label: preset.label, colorHex: preset.colorHex,
                  width: preset.width, height: preset.height)
    }
}

extension CanvasSettingsResponse {
    init(_ canvas: CanvasSettings) {
        self.init(
            stickyPresets: canvas.stickyPresets.map { StickyPresetResponse($0) },
            defaultFontSize: canvas.defaultFontSize,
            defaultTextColorHex: canvas.defaultTextColorHex,
            freeStickyColorHex: canvas.freeStickyColorHex,
            taskStickyColorHex: canvas.taskStickyColorHex,
            initialZoomScale: canvas.initialZoomScale,
            gridSnapInterval: canvas.gridSnapInterval
        )
    }

    /// The canvas-tab defaults, derived from the Domain `CanvasSettings.default` — the single
    /// source for the reset-to-defaults target and the "still at defaults" check in Presentation.
    static let `default` = CanvasSettingsResponse(CanvasSettings.default)
}

extension MarkdownSettingsResponse {
    init(_ markdown: MarkdownSettings) {
        self.init(
            baseFontSize: markdown.baseFontSize,
            headingSizes: markdown.headingSizes,
            codeColorHex: markdown.codeColorHex,
            quoteColorHex: markdown.quoteColorHex,
            useMonospacedFont: markdown.useMonospacedFont,
            codeBlockBackgroundColorHex: markdown.codeBlockBackgroundColorHex,
            quoteBorderColorHex: markdown.quoteBorderColorHex,
            quoteBorderWidth: markdown.quoteBorderWidth,
            linkColorHex: markdown.linkColorHex,
            editorBackgroundColorHex: markdown.editorBackgroundColorHex,
            listIndentExtra: markdown.listIndentExtra,
            listItemSpacing: markdown.listItemSpacing,
            lineSpacing: markdown.lineSpacing,
            syntaxColorOverrides: markdown.syntaxColorOverrides
        )
    }

    /// The markdown-tab defaults, derived from the Domain `MarkdownSettings.default` — the single
    /// source the Presentation `MarkdownAppearance` defaults and the editor's draw-side fallback
    /// read, so no default literal is hand-copied across the import boundary.
    static let `default` = MarkdownSettingsResponse(MarkdownSettings.default)
}
