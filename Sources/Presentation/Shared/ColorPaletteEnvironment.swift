import SwiftUI

// MARK: - Presentation seed palette (neutral home)

/// The Presentation-side seed colour palette, mirroring the Domain `PaletteColor.defaultPalette`
/// (Presentation cannot import the entity). This is the neutral home for the seed — both the
/// Settings feature (`SettingsViewModel.GlobalDefaults`) and the canvas environment fallback read
/// from here, so no shared/canvas file has to reach into a specific feature's ViewModel. The
/// Domain↔mirror match is pinned by `GlobalDefaultsParityTests` via `GlobalDefaults.paletteValues`.
enum PalettePresentationDefaults {
    /// Seed palette values (id-free), mirroring `PaletteColor.defaultPalette`.
    static let values: [(colorHex: String, label: String)] = [
        ("000000", "Black"), ("8E8E93", "Gray"), ("FF3B30", "Red"), ("FF9500", "Orange"),
        ("34C759", "Green"), ("007AFF", "Blue"), ("AF52DE", "Purple"), ("FFFFFF", "White"),
    ]

    /// The seed projected to `PaletteColorResponse`, computed **once** so its element ids are stable
    /// across `body` passes. A fresh-`UUID()`-per-evaluation array would never compare equal, making
    /// `.environment(\.colorPalette, …)` invalidate the whole toolbar subtree on every redraw when
    /// the board palette is empty.
    static let swatches: [PaletteColorResponse] = values.map {
        PaletteColorResponse(id: UUID(), colorHex: $0.colorHex, label: $0.label)
    }
}

// MARK: - Environment key

private struct ColorPaletteKey: EnvironmentKey {
    static let defaultValue: [PaletteColorResponse] = PalettePresentationDefaults.swatches
}

extension EnvironmentValues {
    /// The user-managed global colour palette, injected at two subtree roots:
    ///   • `CardDetailView` (canvas/board route) from `board.settings.global.colorPalette`
    ///   • `SettingsContainerView` (settings route) from the live edited `SettingsViewModel.colorPalette`
    ///
    /// Carries `PaletteColorResponse` directly — Presentation may use Response types, and the
    /// Response is already a `Sendable`/`Equatable`/`Identifiable` display-only struct, so no
    /// separate projection type is needed.
    var colorPalette: [PaletteColorResponse] {
        get { self[ColorPaletteKey.self] }
        set { self[ColorPaletteKey.self] = newValue }
    }
}
