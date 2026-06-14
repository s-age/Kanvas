import Foundation

/// The canvas-sticky use cases, bundled so `BoardViewModel` injects one dependency instead of
/// thirteen — keeping its initializer and body within the length budgets. The canvas-wide `undo`
/// is **not** here: it reverts any element (sticky / shape / connector / image), so it is injected
/// directly into `BoardViewModel` rather than riding along in the sticky bundle.
struct BoardStickyUseCases: Sendable {
    let add: AddStickyUseCase
    let duplicate: DuplicateStickyUseCase
    let edit: EditStickyUseCase
    let setTextColor: SetStickyTextColorUseCase
    let setFillColor: SetStickyFillColorUseCase
    let setFontSize: SetStickyFontSizeUseCase
    let move: MoveStickyUseCase
    let setFrame: SetStickyFrameUseCase
    let bringToFront: BringStickyToFrontUseCase
    let sendToBack: SendStickyToBackUseCase
    let promote: PromoteStickyUseCase
    let demote: DemoteStickyUseCase
    let delete: DeleteStickyUseCase
}
