import Foundation

extension BoardResponseMapper {

    func toTemplateResponse(_ template: BoardTemplate) -> BoardTemplateResponse {
        BoardTemplateResponse(
            settings: settingsResponse(template.settings),
            columns: template.columns
                .sorted { $0.sortIndex < $1.sortIndex }
                .map { col in
                    TemplateColumnResponse(
                        id: col.id,
                        title: col.title,
                        sortIndex: col.sortIndex,
                        isCompletionColumn: col.isCompletionColumn,
                        headerColorHex: col.headerColorHex,
                        headerTextColorHex: col.headerTextColorHex,
                        bodyColorHex: col.bodyColorHex,
                        headerBorderColorHex: col.headerBorderColorHex,
                        bodyBorderColorHex: col.bodyBorderColorHex,
                        indicatorColorHex: col.indicatorColorHex
                    )
                }
        )
    }
}
