import Foundation

/// The multi-board management use cases, bundled so `BoardViewModel` injects one dependency instead
/// of five — keeping its initializer and body within the length budgets. Consumed by the
/// `BoardViewModel+BoardManagement` extension.
struct BoardManagementUseCases: Sendable {
    let list: ListBoardsUseCase
    let add: AddBoardUseCase
    let switchBoard: SwitchBoardUseCase
    let rename: RenameBoardUseCase
    let delete: DeleteBoardUseCase
    /// Live card search over the active board — drives the header search field's filter (ticket
    /// 59B10FBA). Scoped here because search, like the board CRUD, is a board-level concern.
    let search: any SearchCardsUseCase
}
