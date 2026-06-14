import Foundation

/// One column's appearance edit expressed as a keep / clear / set intent per field, resolved
/// **inside** the mutation against the freshly-reloaded column — so the MCP path's single-column
/// edit is one atomic read-modify-write under the store lock, not a load-then-write across two
/// flocks (the TOCTOU `editColumnAppearance` previously had; ticket 620B3601).
///
/// Each colour is a double-optional: `nil` (outer) ⇒ the tool key was omitted ⇒ **keep** the
/// column's current value; `.some(nil)` ⇒ the clear sentinel ⇒ **clear** to the system default;
/// `.some(.some(hex))` ⇒ **set** that hex. `isCompletionColumn` is a plain optional — `nil` keeps,
/// a bool sets. This is a pure data bag (mirroring `EditCardFields`); the keep/clear/set resolution
/// against the live column lives in `BoardManagementService.editColumnAppearance`'s mutate block, the
/// same place `CardService.editing` resolves `EditCardFields`.
struct ColumnAppearanceFields: Sendable, Equatable {
    let headerColorHex: String??
    let headerTextColorHex: String??
    let bodyColorHex: String??
    let headerBorderColorHex: String??
    let bodyBorderColorHex: String??
    let indicatorColorHex: String??
    let isCompletionColumn: Bool?

    init(
        headerColorHex: String?? = nil,
        headerTextColorHex: String?? = nil,
        bodyColorHex: String?? = nil,
        headerBorderColorHex: String?? = nil,
        bodyBorderColorHex: String?? = nil,
        indicatorColorHex: String?? = nil,
        isCompletionColumn: Bool? = nil
    ) {
        self.headerColorHex = headerColorHex
        self.headerTextColorHex = headerTextColorHex
        self.bodyColorHex = bodyColorHex
        self.headerBorderColorHex = headerBorderColorHex
        self.bodyBorderColorHex = bodyBorderColorHex
        self.indicatorColorHex = indicatorColorHex
        self.isCompletionColumn = isCompletionColumn
    }
}
