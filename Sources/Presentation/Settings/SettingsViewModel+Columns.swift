import SwiftUI

// Per-column editing for the Board tab. Structural edits (add / remove / reorder / rename /
// completion) apply only to the Default template scope; colour edits apply to both scopes.
extension SettingsViewModel {

    // MARK: - Colour edits (both scopes)

    func setHeaderColor(_ hex: String?, for id: UUID) {
        guard let index = editableColumns.firstIndex(where: { $0.id == id }) else { return }
        guard editableColumns[index].headerColorHex != hex else { return }
        editableColumns[index].headerColorHex = hex
        markDirty()
    }

    func setHeaderTextColor(_ hex: String?, for id: UUID) {
        guard let index = editableColumns.firstIndex(where: { $0.id == id }) else { return }
        guard editableColumns[index].headerTextColorHex != hex else { return }
        editableColumns[index].headerTextColorHex = hex
        markDirty()
    }

    func setBodyColor(_ hex: String?, for id: UUID) {
        guard let index = editableColumns.firstIndex(where: { $0.id == id }) else { return }
        guard editableColumns[index].bodyColorHex != hex else { return }
        editableColumns[index].bodyColorHex = hex
        markDirty()
    }

    func setHeaderBorderColor(_ hex: String?, for id: UUID) {
        guard let index = editableColumns.firstIndex(where: { $0.id == id }) else { return }
        guard editableColumns[index].headerBorderColorHex != hex else { return }
        editableColumns[index].headerBorderColorHex = hex
        markDirty()
    }

    func setBodyBorderColor(_ hex: String?, for id: UUID) {
        guard let index = editableColumns.firstIndex(where: { $0.id == id }) else { return }
        guard editableColumns[index].bodyBorderColorHex != hex else { return }
        editableColumns[index].bodyBorderColorHex = hex
        markDirty()
    }

    func setIndicatorColor(_ hex: String?, for id: UUID) {
        guard let index = editableColumns.firstIndex(where: { $0.id == id }) else { return }
        guard editableColumns[index].indicatorColorHex != hex else { return }
        editableColumns[index].indicatorColorHex = hex
        markDirty()
    }

    /// Clears every column's colours (the structure is preserved). Used by the Board tab's
    /// "Reset to Defaults" so a reset leaves no leftover per-column tint.
    func clearColumnColors() {
        for index in editableColumns.indices {
            editableColumns[index].headerColorHex = nil
            editableColumns[index].headerTextColorHex = nil
            editableColumns[index].bodyColorHex = nil
            editableColumns[index].headerBorderColorHex = nil
            editableColumns[index].bodyBorderColorHex = nil
            editableColumns[index].indicatorColorHex = nil
        }
    }

    // MARK: - Structural edits (Default template scope only)

    func setColumnTitle(_ title: String, for id: UUID) {
        guard let index = editableColumns.firstIndex(where: { $0.id == id }) else { return }
        guard editableColumns[index].title != title else { return }
        editableColumns[index].title = title
        markDirty()
    }

    func addColumn() {
        editableColumns.append(
            EditableColumn(id: UUID(), title: "New Column", isCompletionColumn: false,
                           headerColorHex: nil, headerTextColorHex: nil, bodyColorHex: nil,
                           headerBorderColorHex: nil, bodyBorderColorHex: nil,
                           indicatorColorHex: nil)
        )
        markDirty()
    }

    func deleteColumn(_ id: UUID) {
        editableColumns.removeAll { $0.id == id }
        markDirty()
    }

    func moveColumnUp(_ id: UUID) {
        guard let index = editableColumns.firstIndex(where: { $0.id == id }), index > 0 else { return }
        editableColumns.swapAt(index, index - 1)
        markDirty()
    }

    func moveColumnDown(_ id: UUID) {
        guard let index = editableColumns.firstIndex(where: { $0.id == id }),
              index < editableColumns.count - 1 else { return }
        editableColumns.swapAt(index, index + 1)
        markDirty()
    }

    /// Toggles the completion ("Done") column. Turning it on makes the column the sole completion
    /// column (clearing any previous holder — at most one per board, the same invariant
    /// `ColumnService.settingCompletion` enforces); turning it off leaves the board with none.
    func setColumnCompletion(_ id: UUID, isOn: Bool) {
        guard editableColumns.contains(where: { $0.id == id }) else { return }
        for i in editableColumns.indices {
            if isOn {
                editableColumns[i].isCompletionColumn = (editableColumns[i].id == id)
            } else if editableColumns[i].id == id {
                editableColumns[i].isCompletionColumn = false
            }
        }
        markDirty()
    }

    func canMoveColumnUp(_ id: UUID) -> Bool {
        (editableColumns.firstIndex { $0.id == id }).map { $0 > 0 } ?? false
    }

    func canMoveColumnDown(_ id: UUID) -> Bool {
        (editableColumns.firstIndex { $0.id == id }).map { $0 < editableColumns.count - 1 } ?? false
    }
}
