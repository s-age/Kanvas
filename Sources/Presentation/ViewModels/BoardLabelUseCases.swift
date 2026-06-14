import Foundation

/// The sticky-label registry use cases (create / edit / delete + per-sticky assignment), bundled so
/// `BoardViewModel` injects one dependency instead of four — keeping its initializer and body within
/// the length budgets. Consumed by the `BoardViewModel+LabelActions` extension.
struct BoardLabelUseCases: Sendable {
    let add: AddLabelUseCase
    let edit: EditLabelUseCase
    let delete: DeleteLabelUseCase
    let toggle: ToggleStickyLabelUseCase
}
