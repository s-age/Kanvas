import Foundation

/// Replaces the whole Default template (settings + column blueprint). The columns are sent verbatim
/// from the settings editor; `toDomain()` reindexes `sortIndex` to array order so a reorder/insert
/// in the UI persists cleanly.
struct EditBoardTemplateRequest: UseCaseRequest {
    let global: GlobalSettingsResponse
    let board: BoardTabSettingsResponse
    let canvas: CanvasSettingsResponse
    let markdown: MarkdownSettingsResponse
    let columns: [TemplateColumnResponse]

    func toDomain() -> BoardTemplate {
        let settings = BoardSettings(
            global: GlobalSettings(
                backgroundColorHex: global.backgroundColorHex,
                textColorHex: global.textColorHex,
                colorPalette: global.colorPalette.map {
                    PaletteColor(id: $0.id, colorHex: $0.colorHex, label: $0.label)
                }
            ),
            board: BoardTabSettings(
                cardSortPolicy: board.cardSortPolicy.toDomain,
                autoCompleteOnMove: board.autoCompleteOnMove,
                cardBackgroundColorHex: board.cardBackgroundColorHex,
                cardTextColorHex: board.cardTextColorHex,
                cardBorderColorHex: board.cardBorderColorHex,
                textColorHex: board.textColorHex,
                newCardPosition: board.newCardPosition.toDomain
            ),
            canvas: CanvasSettings(
                stickyPresets: canvas.stickyPresets.map {
                    StickyPreset(id: $0.id, label: $0.label, colorHex: $0.colorHex,
                                 width: $0.width, height: $0.height)
                },
                defaultFontSize: canvas.defaultFontSize,
                defaultTextColorHex: canvas.defaultTextColorHex,
                freeStickyColorHex: canvas.freeStickyColorHex,
                taskStickyColorHex: canvas.taskStickyColorHex,
                initialZoomScale: canvas.initialZoomScale,
                gridSnapInterval: canvas.gridSnapInterval
            ),
            markdown: MarkdownSettings(
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
        )
        return BoardTemplate(settings: settings, columns: templateColumns())
    }

    private func templateColumns() -> [TemplateColumn] {
        columns.enumerated().map { index, col in
            TemplateColumn(
                id: col.id,
                title: col.title,
                sortIndex: index,
                isCompletionColumn: col.isCompletionColumn,
                headerColorHex: col.headerColorHex,
                headerTextColorHex: col.headerTextColorHex,
                bodyColorHex: col.bodyColorHex,
                headerBorderColorHex: col.headerBorderColorHex,
                bodyBorderColorHex: col.bodyBorderColorHex,
                indicatorColorHex: col.indicatorColorHex
            )
        }
    }
}
