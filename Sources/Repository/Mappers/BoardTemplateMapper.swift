import Foundation

/// DTO ⇄ entity mapping for the app-level Default template. The settings half reuses
/// `BoardSnapshotMapper.settingsEntity` / `.settingsDTO` so the two paths cannot drift.
enum BoardTemplateMapper {

    static func toEntity(_ dto: BoardTemplateDTO) -> BoardTemplate {
        let columns = (dto.columns ?? []).map { col in
            TemplateColumn(
                id: col.id,
                title: col.title,
                sortIndex: col.sortIndex,
                isCompletionColumn: col.isCompletionColumn ?? false,
                headerColorHex: col.headerColorHex,
                headerTextColorHex: col.headerTextColorHex,
                bodyColorHex: col.bodyColorHex,
                headerBorderColorHex: col.headerBorderColorHex,
                bodyBorderColorHex: col.bodyBorderColorHex,
                indicatorColorHex: col.indicatorColorHex
            )
        }
        // An empty/absent column list falls back to the built-in seed so a malformed template can
        // never mint a column-less board.
        let resolvedColumns = columns.isEmpty ? BoardTemplate.default.columns : columns
        return BoardTemplate(
            settings: BoardSnapshotMapper.settingsEntity(dto.settings),
            columns: resolvedColumns
        )
    }

    static func toDTO(_ template: BoardTemplate) -> BoardTemplateDTO {
        BoardTemplateDTO(
            settings: BoardSnapshotMapper.settingsDTO(template.settings),
            columns: template.columns.map { col in
                TemplateColumnDTO(
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
