import AppKit

// MARK: - Grid snap (settings-driven)
//
// World-space snapping applied at the create / move / resize commit points so a sticky (or shape /
// image) lands on the configured grid. A no-op when the grid-snap interval is 0 (off). Split into a
// same-folder extension to keep `CanvasNSView` within the file-length budget.

extension CanvasNSView {

    /// The configured grid-snap interval in world units, or `0` when snapping is off.
    private var gridSnapInterval: CGFloat { CGFloat(canvasSettings?.gridSnapInterval ?? 0) }

    /// Snaps a world-space coordinate to the nearest grid line. A no-op when snapping is off.
    func snap(_ value: CGFloat) -> CGFloat {
        let interval = gridSnapInterval
        guard interval > 0 else { return value }
        return (value / interval).rounded() * interval
    }

    func snap(_ point: CGPoint) -> CGPoint {
        CGPoint(x: snap(point.x), y: snap(point.y))
    }

    /// Snaps a world-space rect by snapping both corners, so the snapped box still spans grid
    /// lines on every edge (the Domain re-clamps the resulting size to valid bounds).
    func snap(_ rect: CGRect) -> CGRect {
        guard gridSnapInterval > 0 else { return rect }
        let minX = snap(rect.minX), minY = snap(rect.minY)
        let maxX = snap(rect.maxX), maxY = snap(rect.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
