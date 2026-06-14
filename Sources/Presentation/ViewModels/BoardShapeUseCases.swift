import Foundation

/// The canvas-shape use cases, bundled so `BoardViewModel` injects one dependency instead of nine
/// — keeping its initializer and body within the length budgets. Consumed by the
/// `BoardViewModel+ShapeActions` extension.
struct BoardShapeUseCases: Sendable {
    let add: AddShapeUseCase
    let move: MoveShapeUseCase
    let resize: ResizeShapeUseCase
    let setStrokeColor: SetShapeStrokeColorUseCase
    let setFillColor: SetShapeFillColorUseCase
    let setStrokeWidth: SetShapeStrokeWidthUseCase
    let bringToFront: BringShapeToFrontUseCase
    let sendToBack: SendShapeToBackUseCase
    let delete: DeleteShapeUseCase
}
