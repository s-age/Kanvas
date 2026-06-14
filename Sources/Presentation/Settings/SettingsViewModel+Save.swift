import SwiftUI

// Save + reset, split out so `SettingsViewModel.swift` stays within the file-length budget.
extension SettingsViewModel {

    func save() async {
        switch selectedScope {
        case .template:
            await saveTemplate()
        case .board(let id):
            await saveBoard(id: id)
        }
    }

    private func saveTemplate() async {
        let request = EditBoardTemplateRequest(
            global: currentGlobal,
            board: currentBoard,
            canvas: currentCanvas,
            markdown: currentMarkdown,
            columns: editableColumns.enumerated().map { index, column in
                TemplateColumnResponse(
                    id: column.id,
                    title: column.title,
                    sortIndex: index,
                    isCompletionColumn: column.isCompletionColumn,
                    headerColorHex: column.headerColorHex,
                    headerTextColorHex: column.headerTextColorHex,
                    bodyColorHex: column.bodyColorHex,
                    headerBorderColorHex: column.headerBorderColorHex,
                    bodyBorderColorHex: column.bodyBorderColorHex,
                    indicatorColorHex: column.indicatorColorHex
                )
            }
        )
        do {
            _ = try await editBoardTemplateUseCase.execute(request)
            markClean()
        } catch {
            self.error = error
        }
    }

    private func saveBoard(id: UUID) async {
        // Settings + every column's colours / completion go in ONE request so the use case applies
        // them in a single transaction — one undo entry, one disk write, no partial-failure split.
        let request = EditBoardSettingsRequest(
            boardID: id,
            global: currentGlobal,
            board: currentBoard,
            canvas: currentCanvas,
            markdown: currentMarkdown,
            columns: editableColumns.map {
                EditBoardSettingsRequest.ColumnAppearance(
                    id: $0.id,
                    headerColorHex: $0.headerColorHex,
                    headerTextColorHex: $0.headerTextColorHex,
                    bodyColorHex: $0.bodyColorHex,
                    headerBorderColorHex: $0.headerBorderColorHex,
                    bodyBorderColorHex: $0.bodyBorderColorHex,
                    indicatorColorHex: $0.indicatorColorHex,
                    isCompletionColumn: $0.isCompletionColumn
                )
            }
        )
        do {
            let response = try await editBoardSettingsUseCase.execute(request)
            // Push the result to the live canvas only when this is the board it is showing; a
            // non-active board is persisted silently (the user's current view never jumps).
            if id == activeBoardID { boardHost.applyBoard(response) }
            markClean()
        } catch {
            self.error = error
        }
    }

    /// Resets the **frontmost** tab to its defaults and persists. Column structure / colours are
    /// left untouched — only the tab's own settings revert.
    func resetActiveTab() async {
        switch selectedTab {
        case .global:
            backgroundColorHex = nil
            textColorHex = nil
            resetPalette()
        case .board:
            cardSortPolicy = .manual
            autoCompleteOnMove = true
            cardBackgroundColorHex = nil
            cardTextColorHex = nil
            cardBorderColorHex = nil
            boardTextColorHex = nil
            newCardPosition = .bottom
            // Per-column colours are part of the Board tab's appearance — clear them too so a
            // "Reset to Defaults" leaves no leftover column tint (structure is preserved).
            clearColumnColors()
        case .canvas:
            resetPresets()
            defaultStickyFontSize = CanvasSettingsResponse.default.defaultFontSize
            defaultStickyTextColorHex = CanvasSettingsResponse.default.defaultTextColorHex
            freeStickyColorHex = CanvasSettingsResponse.default.freeStickyColorHex
            taskStickyColorHex = CanvasSettingsResponse.default.taskStickyColorHex
            initialZoomScale = CanvasSettingsResponse.default.initialZoomScale
            gridSnapInterval = CanvasSettingsResponse.default.gridSnapInterval
        case .markdown:
            markdownBaseFontSize = MarkdownAppearance.defaultBaseFontSize
            markdownHeadingSizes = MarkdownAppearance.defaultHeadingSizes
            markdownCodeColorHex = nil
            markdownQuoteColorHex = nil
            markdownUseMonospacedFont = MarkdownAppearance.defaultUseMonospacedFont
            markdownCodeBlockBackgroundColorHex = nil
            markdownQuoteBorderColorHex = nil
            markdownQuoteBorderWidth = MarkdownAppearance.defaultQuoteBorderWidth
            markdownLinkColorHex = nil
            markdownEditorBackgroundColorHex = nil
            markdownListIndentExtra = 0
            markdownListItemSpacing = 0
            markdownLineSpacing = MarkdownAppearance.defaultLineSpacing
            markdownSyntaxColorOverrides = [:]
        }
        await save()
    }

    // MARK: - Editing state → Response builders

    private var currentGlobal: GlobalSettingsResponse {
        GlobalSettingsResponse(
            backgroundColorHex: backgroundColorHex,
            textColorHex: textColorHex,
            colorPalette: colorPalette.map {
                PaletteColorResponse(id: $0.id, colorHex: $0.colorHex, label: $0.label)
            }
        )
    }

    private var currentBoard: BoardTabSettingsResponse {
        BoardTabSettingsResponse(
            cardSortPolicy: cardSortPolicy,
            autoCompleteOnMove: autoCompleteOnMove,
            cardBackgroundColorHex: cardBackgroundColorHex,
            cardTextColorHex: cardTextColorHex,
            cardBorderColorHex: cardBorderColorHex,
            textColorHex: boardTextColorHex,
            newCardPosition: newCardPosition
        )
    }

    private var currentCanvas: CanvasSettingsResponse {
        CanvasSettingsResponse(
            stickyPresets: stickyPresets.map {
                StickyPresetResponse(id: $0.id, label: $0.label, colorHex: $0.colorHex,
                                     width: $0.width, height: $0.height)
            },
            defaultFontSize: defaultStickyFontSize,
            defaultTextColorHex: defaultStickyTextColorHex,
            freeStickyColorHex: freeStickyColorHex,
            taskStickyColorHex: taskStickyColorHex,
            initialZoomScale: initialZoomScale,
            gridSnapInterval: gridSnapInterval
        )
    }

    private var currentMarkdown: MarkdownSettingsResponse {
        MarkdownSettingsResponse(
            baseFontSize: markdownBaseFontSize,
            headingSizes: markdownHeadingSizes,
            codeColorHex: markdownCodeColorHex,
            quoteColorHex: markdownQuoteColorHex,
            useMonospacedFont: markdownUseMonospacedFont,
            codeBlockBackgroundColorHex: markdownCodeBlockBackgroundColorHex,
            quoteBorderColorHex: markdownQuoteBorderColorHex,
            quoteBorderWidth: markdownQuoteBorderWidth,
            linkColorHex: markdownLinkColorHex,
            editorBackgroundColorHex: markdownEditorBackgroundColorHex,
            listIndentExtra: markdownListIndentExtra,
            listItemSpacing: markdownListItemSpacing,
            lineSpacing: markdownLineSpacing,
            syntaxColorOverrides: markdownSyntaxColorOverrides
        )
    }
}
