import Foundation

/// The Kanban column + card CRUD use cases, bundled so `BoardViewModel` injects one dependency
/// instead of nine — keeping its initializer and body within the length budgets. Consumed by the
/// `BoardViewModel+ColumnActions` and `BoardViewModel+CardActions` extensions.
struct BoardKanbanUseCases: Sendable {
    let addColumn: AddColumnUseCase
    let renameColumn: RenameColumnUseCase
    let setCompletionColumn: SetCompletionColumnUseCase
    let reorderColumn: ReorderColumnUseCase
    let deleteColumn: DeleteColumnUseCase
    let addCard: AddCardUseCase
    let editCard: EditCardUseCase
    let moveCard: MoveCardUseCase
    let deleteCard: DeleteCardUseCase
}
