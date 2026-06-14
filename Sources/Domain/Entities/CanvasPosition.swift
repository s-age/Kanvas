struct CanvasPosition: Sendable, Equatable {
    var x: Double
    var y: Double

    static let zero = CanvasPosition(x: 0, y: 0)
}
