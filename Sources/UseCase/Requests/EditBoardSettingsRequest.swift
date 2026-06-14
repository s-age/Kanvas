import Foundation

struct EditBoardSettingsRequest: UseCaseRequest {
    /// One column's appearance + completion flag, applied in the same atomic mutation as the
    /// board settings so a single "Save" is one undo entry / one disk write.
    struct ColumnAppearance: Sendable {
        let id: UUID
        let headerColorHex: String?
        let headerTextColorHex: String?
        let bodyColorHex: String?
        let headerBorderColorHex: String?
        let bodyBorderColorHex: String?
        let indicatorColorHex: String?
        let isCompletionColumn: Bool
    }

    /// Which board to update. The settings window's sidebar can edit any board, not only the
    /// active one — the use case persists this board without switching the active board.
    let boardID: UUID
    let global: GlobalSettingsResponse
    let board: BoardTabSettingsResponse
    let canvas: CanvasSettingsResponse
    let markdown: MarkdownSettingsResponse
    /// Per-column colours + completion for this board's columns. Applied alongside `board` in one
    /// transaction. Empty leaves the columns untouched.
    let columns: [ColumnAppearance]

    func toDomain() -> BoardSettings {
        BoardSettings(
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
    }
}
