import SwiftUI

extension KanbanBoardView {

    /// The board's alert + confirmation-dialog stack, factored out of `body` (in `KanbanBoardView`)
    /// to keep that file within the file/type length budgets. Applied as one call in `body`:
    /// `boardModals(boardContent)`. Split into `boardAlerts` + `boardConfirmations` so each stays
    /// within the function-body length budget.
    func boardModals(_ content: some View) -> some View {
        boardConfirmations(boardAlerts(content))
    }

    @ViewBuilder
    private func boardAlerts(_ content: some View) -> some View {
        content
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.error != nil },
                    set: { if !$0 { viewModel.dismissError() } }
                )
            ) {
                Button("OK") { viewModel.dismissError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            // A benign, informational notice (e.g. an undo skipped because another process edited
            // the board) — kept separate from the "Error" alert so it isn't mislabelled as a
            // failure. Title travels with the notice (`UserNotice`), so this alert isn't undo-bound.
            .alert(
                viewModel.notice?.title ?? "",
                isPresented: Binding(
                    get: { viewModel.notice != nil },
                    set: { if !$0 { viewModel.dismissNotice() } }
                )
            ) {
                Button("OK") { viewModel.dismissNotice() }
            } message: {
                Text(viewModel.notice?.message ?? "")
            }
            .alert("Rename Board", isPresented: $isRenamingBoard) {
                TextField("Board name", text: $boardRenameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let title = boardRenameText.trimmingCharacters(in: .whitespaces)
                    guard !title.isEmpty else { return }
                    Task { await viewModel.renameActiveBoard(title: title) }
                }
            }
    }

    @ViewBuilder
    private func boardConfirmations(_ content: some View) -> some View {
        content
            .confirmationDialog(
                "Delete Card?",
                isPresented: Binding(
                    get: { cardIDToDelete != nil },
                    set: { if !$0 { cardIDToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let id = cardIDToDelete {
                        Task { await viewModel.deleteCard(id: id) }
                    }
                }
            }
            .confirmationDialog(
                "Delete Column?",
                isPresented: Binding(
                    get: { columnIDToDelete != nil },
                    set: { if !$0 { columnIDToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let id = columnIDToDelete {
                        Task { await viewModel.deleteColumn(id: id) }
                    }
                }
            } message: {
                Text("All cards in this column will also be deleted.")
            }
    }
}
