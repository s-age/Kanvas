import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {

    /// Which tab is frontmost — drives the footer's tab-aware "Reset to Defaults" button.
    enum Tab: Hashable {
        case global
        case board
        case canvas
        case markdown
    }

    /// What the sidebar is editing: the app-level Default template, or one specific board.
    enum Scope: Hashable {
        case template
        case board(UUID)
    }

    /// A column shown in the Board tab's per-column colour editor. For the Default template the
    /// whole row is editable (title / completion / add / remove / reorder); for a real board only
    /// the colours are (the structure is managed on the board itself).
    struct EditableColumn: Identifiable, Hashable {
        let id: UUID
        var title: String
        var isCompletionColumn: Bool
        var headerColorHex: String?      // header background
        var headerTextColorHex: String?  // header text
        var bodyColorHex: String?        // body (card-stack area) background
        var headerBorderColorHex: String? // header border
        var bodyBorderColorHex: String?   // body border
        var indicatorColorHex: String?    // status-indicator dot
    }

    /// One row in the Canvas tab's sticky-preset editor — a palette preset's label, fill colour,
    /// and absolute size. Edited inline (add / remove / recolour / resize); persisted to
    /// `CanvasSettings.stickyPresets` on save.
    struct EditablePreset: Identifiable, Hashable {
        let id: UUID
        var label: String
        var colorHex: String
        var width: Double
        var height: Double
    }

    /// One row in the Global tab's colour-palette editor — a palette colour's fill and optional
    /// label. Edited inline (add / remove / recolour / relabel / reorder); persisted to
    /// `GlobalSettings.colorPalette` on save.
    struct EditablePaletteColor: Identifiable, Hashable {
        let id: UUID
        var colorHex: String
        var label: String
    }

    var selectedTab: Tab = .global
    var selectedScope: Scope = .template
    /// Guards `prepareInitialScope()` so the first-open default-to-active-board runs only once.
    private var hasPreparedScope = false

    /// The Board tab's per-column colour rows for the current scope.
    var editableColumns: [EditableColumn] = []

    // MARK: - Global tab editing state
    //
    // The palette default mirrors the Domain `PaletteColor.defaultPalette` seed (Presentation
    // cannot import the entity), re-declared once in `GlobalDefaults` and referenced by property
    // init, `load()`, `resetActiveTab()`, and `canResetActiveTab`. The Domain↔mirror match is
    // pinned by `GlobalDefaultsParityTests`.

    /// Single source for the Global tab's seed colour palette within Presentation.
    enum GlobalDefaults {
        /// Seed palette values (id-free), mirroring `PaletteColor.defaultPalette`. The literals live
        /// in `PalettePresentationDefaults` (the neutral Shared home); this forwards to them so the
        /// `GlobalDefaultsParityTests` Domain↔mirror pin still anchors on this name.
        static let paletteValues = PalettePresentationDefaults.values
        /// A fresh seeded palette (new ids each call).
        static func seededPalette() -> [EditablePaletteColor] {
            paletteValues.map { EditablePaletteColor(id: UUID(), colorHex: $0.colorHex, label: $0.label) }
        }
    }

    var backgroundColorHex: String?
    var textColorHex: String?
    var colorPalette: [EditablePaletteColor] = GlobalDefaults.seededPalette()

    /// The live in-progress palette projected to `PaletteColorResponse` for injection into
    /// `@Environment(\.colorPalette)` (ticket 5EA3E652). Projecting it here — rather than re-mapping
    /// an ad-hoc closure inside `SettingsContainerView.body` — keeps the one legitimate
    /// `EditablePaletteColor → PaletteColorResponse` mapping in a single place and reads through the
    /// observable. Because `PaletteColorResponse` (and therefore `[PaletteColorResponse]`) is
    /// `Equatable`, SwiftUI's `.environment(\.colorPalette, …)` only re-propagates the value down the
    /// settings subtree when the palette content actually changes, so an unrelated re-render no longer
    /// invalidates every colour-picking control (the `peak` half of 5EA3E652).
    var colorPaletteResponses: [PaletteColorResponse] {
        colorPalette.map {
            PaletteColorResponse(id: $0.id, colorHex: $0.colorHex, label: $0.label)
        }
    }

    // MARK: - Board tab editing state

    var cardSortPolicy: CardSortPolicyResponse = .manual
    var autoCompleteOnMove: Bool = true
    var cardBackgroundColorHex: String?
    var cardTextColorHex: String?
    var cardBorderColorHex: String?
    var boardTextColorHex: String?
    var newCardPosition: NewCardPositionResponse = .bottom

    // MARK: - Canvas tab editing state
    //
    // Defaults come straight from `CanvasSettingsResponse.default` (derived from the Domain
    // `CanvasSettings.default` in the UseCase layer), so every reset target / "still at defaults"
    // check reads the single Domain source — no Presentation-side mirror to drift.
    // `defaultStickyTextColorHex` is a concrete default colour (the "auto" background-brightness
    // sentinel is retired — text colour is always an explicit hex).

    var stickyPresets: [EditablePreset] = SettingsViewModel.seededPresets()
    var defaultStickyFontSize = CanvasSettingsResponse.default.defaultFontSize
    var defaultStickyTextColorHex = CanvasSettingsResponse.default.defaultTextColorHex
    var freeStickyColorHex = CanvasSettingsResponse.default.freeStickyColorHex
    var taskStickyColorHex = CanvasSettingsResponse.default.taskStickyColorHex
    var initialZoomScale = CanvasSettingsResponse.default.initialZoomScale
    var gridSnapInterval = CanvasSettingsResponse.default.gridSnapInterval

    // MARK: - Markdown tab editing state
    //
    // Defaults mirror the Domain `MarkdownSettings.init` defaults, re-declared once in
    // `MarkdownAppearance` (Presentation cannot import the entity) and shared with the editor's
    // `MarkdownTheme` fallback. `codeColorHex` / `quoteColorHex` are `nil` = "use the default
    // colour"; the picker shows `MarkdownAppearance.code/quoteDefaultHex` in that case.

    var markdownBaseFontSize = MarkdownAppearance.defaultBaseFontSize
    var markdownHeadingSizes = MarkdownAppearance.defaultHeadingSizes
    var markdownCodeColorHex: String?
    var markdownQuoteColorHex: String?
    var markdownUseMonospacedFont = MarkdownAppearance.defaultUseMonospacedFont
    var markdownCodeBlockBackgroundColorHex: String?
    var markdownQuoteBorderColorHex: String?
    var markdownQuoteBorderWidth = MarkdownAppearance.defaultQuoteBorderWidth
    var markdownLinkColorHex: String?
    /// Markdown-editor background override (hex); `nil` = inherit from Global/system.
    var markdownEditorBackgroundColorHex: String?
    var markdownListIndentExtra: Double = 0
    var markdownListItemSpacing: Double = 0
    var markdownLineSpacing = MarkdownAppearance.defaultLineSpacing
    /// Per-token-kind code-block syntax-highlight colour overrides (token-kind key → hex). An absent
    /// key inherits the built-in GitHub Primer palette colour; empty (the default) = built-in only.
    var markdownSyntaxColorOverrides: [String: String] = [:]

    private(set) var isDirty = false
    var error: (any Error)?

    /// Which board the canvas currently shows — an edit to it is pushed back to the live board.
    var activeBoardID: UUID? { boardHost.activeBoardID }

    /// Sidebar entries: "Default" first, then every board in display order.
    var scopes: [Scope] { [.template] + boardHost.boards.map { .board($0.id) } }

    var isTemplateScope: Bool { selectedScope == .template }

    func scopeTitle(_ scope: Scope) -> String {
        switch scope {
        case .template: return "Default"
        case .board(let id): return boardHost.boards.first { $0.id == id }?.title ?? "Board"
        }
    }

    // MARK: - Dependencies

    let boardHost: any BoardSettingsHost
    let editBoardSettingsUseCase: EditBoardSettingsUseCase
    let loadBoardByIDUseCase: LoadBoardByIDUseCase
    let loadBoardTemplateUseCase: any LoadBoardTemplateUseCase
    let editBoardTemplateUseCase: EditBoardTemplateUseCase

    init(
        boardHost: any BoardSettingsHost,
        editBoardSettings: EditBoardSettingsUseCase,
        loadBoardByID: LoadBoardByIDUseCase,
        loadBoardTemplate: any LoadBoardTemplateUseCase,
        editBoardTemplate: EditBoardTemplateUseCase
    ) {
        self.boardHost = boardHost
        self.editBoardSettingsUseCase = editBoardSettings
        self.loadBoardByIDUseCase = loadBoardByID
        self.loadBoardTemplateUseCase = loadBoardTemplate
        self.editBoardTemplateUseCase = editBoardTemplate
    }

    // MARK: - Actions

    /// On first open, default the sidebar selection to the board the canvas is showing (so opening
    /// settings edits the current board, matching the prior single-scope behaviour). Runs once.
    func prepareInitialScope() {
        guard !hasPreparedScope else { return }
        hasPreparedScope = true
        if let active = boardHost.activeBoardID {
            selectedScope = .board(active)
        }
    }

    func markDirty() {
        isDirty = true
    }

    /// Clears the dirty flag after a load or a successful save. Lives on the class so the
    /// same-type extensions (which cannot reach the `private(set)` setter) can call it.
    func markClean() {
        isDirty = false
    }

    /// Whether the frontmost tab holds any non-default value — drives the footer reset button.
    var canResetActiveTab: Bool {
        switch selectedTab {
        case .global:
            return backgroundColorHex != nil || textColorHex != nil || !paletteIsDefault
        case .board:
            return cardSortPolicy != .manual
                || !autoCompleteOnMove
                || cardBackgroundColorHex != nil
                || cardTextColorHex != nil
                || cardBorderColorHex != nil
                || boardTextColorHex != nil
                || newCardPosition != .bottom
                || editableColumns.contains {
                    $0.headerColorHex != nil || $0.headerTextColorHex != nil || $0.bodyColorHex != nil
                        || $0.headerBorderColorHex != nil || $0.bodyBorderColorHex != nil
                        || $0.indicatorColorHex != nil
                }
        case .canvas:
            return !stickyPresetsAreDefault
                || defaultStickyFontSize != CanvasSettingsResponse.default.defaultFontSize
                || defaultStickyTextColorHex != CanvasSettingsResponse.default.defaultTextColorHex
                || freeStickyColorHex != CanvasSettingsResponse.default.freeStickyColorHex
                || taskStickyColorHex != CanvasSettingsResponse.default.taskStickyColorHex
                || initialZoomScale != CanvasSettingsResponse.default.initialZoomScale
                || gridSnapInterval != CanvasSettingsResponse.default.gridSnapInterval
        case .markdown:
            return markdownBaseFontSize != MarkdownAppearance.defaultBaseFontSize
                || markdownHeadingSizes != MarkdownAppearance.defaultHeadingSizes
                || markdownCodeColorHex != nil
                || markdownQuoteColorHex != nil
                || markdownUseMonospacedFont != MarkdownAppearance.defaultUseMonospacedFont
                || markdownCodeBlockBackgroundColorHex != nil
                || markdownQuoteBorderColorHex != nil
                || markdownQuoteBorderWidth != MarkdownAppearance.defaultQuoteBorderWidth
                || markdownLinkColorHex != nil
                || markdownEditorBackgroundColorHex != nil
                || markdownListIndentExtra != 0
                || markdownListItemSpacing != 0
                || markdownLineSpacing != MarkdownAppearance.defaultLineSpacing
                || !markdownSyntaxColorOverrides.isEmpty
        }
    }

    func dismissError() {
        error = nil
    }
}
