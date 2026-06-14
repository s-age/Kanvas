import Foundation

/// Edits **one** column's colours + completion flag on the **active** board, applied as a single
/// atomic read-modify-write inside the store lock (no lost-update window for sibling columns — the
/// reason this exists separately from the batch `EditBoardSettingsRequest`; ticket 620B3601). The
/// MCP `board_column_appearance_edit` tool targets the active board implicitly (mirroring the former
/// `loadActiveBoard` read); the service resolves "active" inside the store lock, so the request
/// carries only the column id.
///
/// Each colour is a double-optional keep/clear/set intent: `nil` ⇒ keep the column's current value;
/// `.some(nil)` ⇒ clear to the system default; `.some(.some(hex))` ⇒ set. `isCompletionColumn`
/// keeps on `nil`, sets on a bool.
///
/// Hex format is validated here in the Request layer — the validation boundary — so the MCP path and
/// the GUI converge on one format: bare 6-digit, the same rule `LabelValidation` enforces and the
/// form `Color.toHex` / the store seed emit. Only a *set* value (`.some(.some(hex))`) is checked;
/// keep (`nil`) and clear (`.some(nil)`) carry no hex. (ticket C5994D2A)
struct EditColumnAppearanceRequest: ValidatableRequest {
    let columnID: UUID
    let headerColorHex: String??
    let headerTextColorHex: String??
    let bodyColorHex: String??
    let headerBorderColorHex: String??
    let bodyBorderColorHex: String??
    let indicatorColorHex: String??
    let isCompletionColumn: Bool?

    func validate() throws {
        let setOrCleared = [
            headerColorHex, headerTextColorHex, bodyColorHex,
            headerBorderColorHex, bodyBorderColorHex, indicatorColorHex
        ].compactMap { $0 }  // drop "keep" (outer nil)
        for colour in setOrCleared {
            guard let hex = colour else { continue }  // skip "clear" (.some(nil))
            try LabelValidation.validate(colorHex: hex)
        }
    }

    func toDomain() -> ColumnAppearanceFields {
        ColumnAppearanceFields(
            headerColorHex: headerColorHex,
            headerTextColorHex: headerTextColorHex,
            bodyColorHex: bodyColorHex,
            headerBorderColorHex: headerBorderColorHex,
            bodyBorderColorHex: bodyBorderColorHex,
            indicatorColorHex: indicatorColorHex,
            isCompletionColumn: isCompletionColumn
        )
    }
}
