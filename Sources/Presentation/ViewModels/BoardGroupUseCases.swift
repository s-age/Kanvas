import Foundation

/// The canvas group (multi-select) use cases, bundled so `BoardViewModel` injects one dependency
/// instead of two. Consumed by the `BoardViewModel+MultiSelectActions` extension — group move /
/// delete each apply as one batch mutation (one undo entry — ticket 4FF14DCF).
struct BoardGroupUseCases: Sendable {
    let move: MoveCanvasGroupUseCase
    let delete: DeleteCanvasGroupUseCase
}
