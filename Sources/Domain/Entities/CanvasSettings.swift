struct CanvasSettings: Sendable, Equatable {
    /// The palette's drag-to-create presets (label / colour / absolute size). Replaces the former
    /// single default sticky size — each preset now carries its own absolute dimensions.
    var stickyPresets: [StickyPreset]
    var defaultFontSize: Double
    var defaultTextColorHex: String
    var freeStickyColorHex: String?
    var taskStickyColorHex: String?
    var initialZoomScale: Double
    var gridSnapInterval: Double

    static let minZoom: Double = 0.1
    static let maxZoom: Double = 5.0

    init(
        stickyPresets: [StickyPreset] = StickyPreset.defaultPresets,
        defaultFontSize: Double = 13,
        defaultTextColorHex: String = StickyTextStyle.defaultColorHex,
        freeStickyColorHex: String? = nil,
        taskStickyColorHex: String? = nil,
        initialZoomScale: Double = 1.0,
        gridSnapInterval: Double = 0
    ) {
        self.stickyPresets = stickyPresets
        self.defaultFontSize = min(max(defaultFontSize, StickyTextStyle.minFontSize), StickyTextStyle.maxFontSize)
        // Coerce the retired "auto" sentinel to the concrete default (same rule as StickyTextStyle).
        self.defaultTextColorHex = StickyTextStyle.normalizedColorHex(defaultTextColorHex)
        self.freeStickyColorHex = freeStickyColorHex
        self.taskStickyColorHex = taskStickyColorHex
        self.initialZoomScale = min(max(initialZoomScale, CanvasSettings.minZoom), CanvasSettings.maxZoom)
        self.gridSnapInterval = max(gridSnapInterval, 0)
    }

    static let `default` = CanvasSettings()
}
