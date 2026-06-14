/// The attributes a palette preset dictates when a sticky is created — its centre `position`,
/// `size`, and optional `fillColorHex` (`nil` = inherit the board's free/task default fill).
/// Bundling them keeps the creation API (`StickyService.adding`) to a single argument instead of
/// threading position / size / colour separately.
struct StickyPlacement: Sendable, Equatable {
    var position: CanvasPosition
    var size: StickySize
    var fillColorHex: String?

    init(position: CanvasPosition, size: StickySize, fillColorHex: String? = nil) {
        self.position = position
        self.size = size
        self.fillColorHex = fillColorHex
    }
}
