struct GlobalSettings: Sendable, Equatable {
    var backgroundColorHex: String?
    var textColorHex: String?
    /// The user-managed colour palette (ordered). Seeded with `PaletteColor.defaultPalette`; an
    /// explicitly emptied palette persists as `[]` (the user may clear it — the OS picker is still
    /// reachable when editing the palette itself).
    var colorPalette: [PaletteColor]

    init(
        backgroundColorHex: String? = nil,
        textColorHex: String? = nil,
        colorPalette: [PaletteColor] = PaletteColor.defaultPalette
    ) {
        self.backgroundColorHex = backgroundColorHex
        self.textColorHex = textColorHex
        self.colorPalette = colorPalette
    }

    static let `default` = GlobalSettings()
}
