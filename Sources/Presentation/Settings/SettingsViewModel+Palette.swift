import SwiftUI

// Colour-palette editing for the Global tab — add / remove / recolour / relabel / reorder the
// managed palette colours. Scope-independent (the palette is part of `GlobalSettings`, applied to
// whichever scope is loaded). Each setter guards same-value write-backs so a redraw never marks the
// form dirty (the same pattern as `SettingsViewModel+Presets` / `+Columns`).
extension SettingsViewModel {

    /// The longest a palette label may be — mirrors the Domain `PaletteColor` truncation.
    static let maxPaletteLabelLength = 40

    func setPaletteColor(_ hex: String, for id: UUID) {
        guard let index = colorPalette.firstIndex(where: { $0.id == id }) else { return }
        guard colorPalette[index].colorHex.caseInsensitiveCompare(hex) != .orderedSame else { return }
        colorPalette[index].colorHex = hex
        markDirty()
    }

    func setPaletteLabel(_ label: String, for id: UUID) {
        let trimmed = String(label.prefix(Self.maxPaletteLabelLength))
        guard let index = colorPalette.firstIndex(where: { $0.id == id }) else { return }
        guard colorPalette[index].label != trimmed else { return }
        colorPalette[index].label = trimmed
        markDirty()
    }

    /// Appends a new palette colour seeded mid-grey with an empty label.
    func addPaletteColor() {
        colorPalette.append(EditablePaletteColor(id: UUID(), colorHex: "8E8E93", label: ""))
        markDirty()
    }

    func deletePaletteColor(_ id: UUID) {
        colorPalette.removeAll { $0.id == id }
        markDirty()
    }

    /// Reorders the palette (driven by the list's `.onMove`).
    func movePaletteColor(fromOffsets: IndexSet, toOffset: Int) {
        colorPalette.move(fromOffsets: fromOffsets, toOffset: toOffset)
        markDirty()
    }

    /// Resets the palette to the seeded set (fresh ids). Used by the Global tab's "Reset to
    /// Defaults".
    func resetPalette() {
        colorPalette = GlobalDefaults.seededPalette()
    }

    /// Whether the palette still matches the seeded set (ids ignored) — drives the Global tab's
    /// reset button.
    var paletteIsDefault: Bool {
        let seed = GlobalDefaults.paletteValues
        guard colorPalette.count == seed.count else { return false }
        return zip(colorPalette, seed).allSatisfy { color, defaults in
            color.colorHex.caseInsensitiveCompare(defaults.colorHex) == .orderedSame
                && color.label == defaults.label
        }
    }
}
