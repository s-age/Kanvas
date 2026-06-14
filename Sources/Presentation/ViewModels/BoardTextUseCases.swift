import Foundation

/// The canvas free-text use cases, bundled so `BoardViewModel` injects one dependency instead of
/// nine — keeping its initializer and body within the length budgets. Consumed by the
/// `BoardViewModel+TextActions` extension.
struct BoardTextUseCases: Sendable {
    let add: AddTextUseCase
    let duplicate: DuplicateTextUseCase
    let edit: EditTextUseCase
    let move: MoveTextUseCase
    let resize: ResizeTextUseCase
    let setColor: SetTextColorUseCase
    let setFontSize: SetTextFontSizeUseCase
    let bringToFront: BringTextToFrontUseCase
    let sendToBack: SendTextToBackUseCase
    let delete: DeleteTextUseCase
}
