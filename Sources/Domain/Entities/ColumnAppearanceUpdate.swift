import Foundation

/// One column's appearance + completion flag for a board-settings save, applied alongside the
/// board settings in a single mutation (one undo entry / one disk write). The UseCase maps the
/// Request's per-column input into these so the Service never sees Request types.
struct ColumnAppearanceUpdate: Sendable, Equatable {
    let id: Column.ID
    let colors: ColumnColors
    let isCompletionColumn: Bool
}
