import SwiftUI

// Sticky-preset editing for the Canvas tab — add / remove / recolour / resize / relabel the
// palette presets. Scope-independent (presets are part of `CanvasSettings`, applied to whichever
// scope is loaded). Each setter guards same-value write-backs so a redraw never marks the form
// dirty (the same pattern as `SettingsViewModel+Columns`).
extension SettingsViewModel {

    /// The longest a preset label may be — mirrors the Domain `StickyPreset` truncation. The
    /// label TextField has no length limiter of its own; `setPresetLabel` truncates here, and the
    /// field re-renders from the truncated stored value, so a 4th character is dropped on commit.
    static let maxPresetLabelLength = 3

    /// A fresh editable copy of the default S/M/L preset set (new ids each call), sourced from
    /// `CanvasSettingsResponse.default` — i.e. the Domain `StickyPreset.defaultPresets`. Used to
    /// seed a new editor and to power "Reset to Defaults".
    static func seededPresets() -> [EditablePreset] {
        CanvasSettingsResponse.default.stickyPresets.map {
            EditablePreset(id: UUID(), label: $0.label, colorHex: $0.colorHex,
                           width: $0.width, height: $0.height)
        }
    }

    func setPresetLabel(_ label: String, for id: UUID) {
        let trimmed = String(label.prefix(Self.maxPresetLabelLength))
        guard let index = stickyPresets.firstIndex(where: { $0.id == id }) else { return }
        guard stickyPresets[index].label != trimmed else { return }
        stickyPresets[index].label = trimmed
        markDirty()
    }

    func setPresetColor(_ hex: String, for id: UUID) {
        guard let index = stickyPresets.firstIndex(where: { $0.id == id }) else { return }
        guard stickyPresets[index].colorHex != hex else { return }
        stickyPresets[index].colorHex = hex
        markDirty()
    }

    func setPresetWidth(_ width: Double, for id: UUID) {
        guard let index = stickyPresets.firstIndex(where: { $0.id == id }) else { return }
        guard stickyPresets[index].width != width else { return }
        stickyPresets[index].width = width
        markDirty()
    }

    func setPresetHeight(_ height: Double, for id: UUID) {
        guard let index = stickyPresets.firstIndex(where: { $0.id == id }) else { return }
        guard stickyPresets[index].height != height else { return }
        stickyPresets[index].height = height
        markDirty()
    }

    /// Appends a new preset seeded from the Medium default size and the free-sticky fill colour.
    func addPreset() {
        stickyPresets.append(
            EditablePreset(id: UUID(), label: "", colorHex: StickyAppearance.freeStickyDefaultHex,
                           width: 200, height: 150)
        )
        markDirty()
    }

    func deletePreset(_ id: UUID) {
        stickyPresets.removeAll { $0.id == id }
        markDirty()
    }

    /// Resets the preset list to the seeded S/M/L set (fresh ids). Used by the Canvas tab's
    /// "Reset to Defaults".
    func resetPresets() {
        stickyPresets = Self.seededPresets()
    }

    /// Whether the preset list still matches the seeded S/M/L set (ids ignored) — drives the
    /// Canvas tab's reset button.
    var stickyPresetsAreDefault: Bool {
        let seed = CanvasSettingsResponse.default.stickyPresets
        guard stickyPresets.count == seed.count else { return false }
        return zip(stickyPresets, seed).allSatisfy { preset, defaults in
            preset.label == defaults.label
                && preset.colorHex == defaults.colorHex
                && preset.width == defaults.width
                && preset.height == defaults.height
        }
    }
}
