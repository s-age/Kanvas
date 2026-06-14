import SwiftUI

// Scope-aware loading, split out so `SettingsViewModel.swift` stays within the file-length budget.
extension SettingsViewModel {

    func load() async {
        switch selectedScope {
        case .template:
            await loadTemplate()
        case .board(let id):
            await loadBoard(id: id)
        }
    }

    private func loadTemplate() async {
        do {
            let response = try await loadBoardTemplateUseCase.execute()
            applyLoadedSettings(response.settings)
            editableColumns = response.columns.map(Self.editableColumn)
            markClean()
        } catch is CancellationError {
            // The settings view disappeared mid-load — no one is waiting. (See arch-presentation.)
        } catch {
            self.error = error
        }
    }

    private func loadBoard(id: UUID) async {
        do {
            let response = try await loadBoardByIDUseCase.execute(LoadBoardByIDRequest(boardID: id))
            applyLoadedSettings(response.settings)
            editableColumns = response.columns
                .sorted { $0.sortIndex < $1.sortIndex }
                .map {
                    EditableColumn(
                        id: $0.id,
                        title: $0.title,
                        isCompletionColumn: $0.isCompletionColumn,
                        headerColorHex: $0.headerColorHex,
                        headerTextColorHex: $0.headerTextColorHex,
                        bodyColorHex: $0.bodyColorHex,
                        headerBorderColorHex: $0.headerBorderColorHex,
                        bodyBorderColorHex: $0.bodyBorderColorHex,
                        indicatorColorHex: $0.indicatorColorHex
                    )
                }
            markClean()
        } catch is CancellationError {
            // The settings view disappeared mid-load — no one is waiting. (See arch-presentation.)
        } catch {
            self.error = error
        }
    }

    private static func editableColumn(_ column: TemplateColumnResponse) -> EditableColumn {
        EditableColumn(
            id: column.id,
            title: column.title,
            isCompletionColumn: column.isCompletionColumn,
            headerColorHex: column.headerColorHex,
            headerTextColorHex: column.headerTextColorHex,
            bodyColorHex: column.bodyColorHex,
            headerBorderColorHex: column.headerBorderColorHex,
            bodyBorderColorHex: column.bodyBorderColorHex,
            indicatorColorHex: column.indicatorColorHex
        )
    }

    /// Populates every tab's editing state from a loaded settings response. Shared by the template
    /// and board load paths.
    private func applyLoadedSettings(_ settings: BoardSettingsResponse) {
        backgroundColorHex = settings.global.backgroundColorHex
        textColorHex = settings.global.textColorHex
        colorPalette = settings.global.colorPalette.map {
            EditablePaletteColor(id: $0.id, colorHex: $0.colorHex, label: $0.label)
        }
        let board = settings.board
        cardSortPolicy = board.cardSortPolicy
        autoCompleteOnMove = board.autoCompleteOnMove
        cardBackgroundColorHex = board.cardBackgroundColorHex
        cardTextColorHex = board.cardTextColorHex
        cardBorderColorHex = board.cardBorderColorHex
        boardTextColorHex = board.textColorHex
        newCardPosition = board.newCardPosition
        let canvas = settings.canvas
        stickyPresets = canvas.stickyPresets.map {
            EditablePreset(id: $0.id, label: $0.label, colorHex: $0.colorHex,
                           width: $0.width, height: $0.height)
        }
        defaultStickyFontSize = canvas.defaultFontSize
        defaultStickyTextColorHex = canvas.defaultTextColorHex
        freeStickyColorHex = canvas.freeStickyColorHex
        taskStickyColorHex = canvas.taskStickyColorHex
        initialZoomScale = canvas.initialZoomScale
        gridSnapInterval = canvas.gridSnapInterval
        let markdown = settings.markdown
        markdownBaseFontSize = markdown.baseFontSize
        markdownHeadingSizes = markdown.headingSizes
        markdownCodeColorHex = markdown.codeColorHex
        markdownQuoteColorHex = markdown.quoteColorHex
        markdownUseMonospacedFont = markdown.useMonospacedFont
        markdownCodeBlockBackgroundColorHex = markdown.codeBlockBackgroundColorHex
        markdownQuoteBorderColorHex = markdown.quoteBorderColorHex
        markdownQuoteBorderWidth = markdown.quoteBorderWidth
        markdownLinkColorHex = markdown.linkColorHex
        markdownEditorBackgroundColorHex = markdown.editorBackgroundColorHex
        markdownListIndentExtra = markdown.listIndentExtra
        markdownListItemSpacing = markdown.listItemSpacing
        markdownLineSpacing = markdown.lineSpacing
        markdownSyntaxColorOverrides = markdown.syntaxColorOverrides
    }
}
