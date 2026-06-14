import SwiftUI

// The toolbar board switcher: a menu listing every board (checkmark on the active one) plus
// New / Rename / Delete actions. Split into a sibling file so `KanbanBoardView.swift` stays within
// the file-length budget; it drives the parent's `isRenamingBoard` / `boardRenameText` state.

extension KanbanBoardView {

    var boardPicker: some View {
        Menu {
            ForEach(viewModel.boards) { board in
                Button {
                    Task { await viewModel.switchBoard(to: board.id) }
                } label: {
                    if board.id == viewModel.activeBoardID {
                        Label(board.title, systemImage: "checkmark")
                    } else {
                        Text(board.title)
                    }
                }
            }
            Divider()
            Button("New Board") {
                Task { await viewModel.addBoard(title: "New Board") }
            }
            Button("Rename Board…") {
                boardRenameText = viewModel.activeBoardTitle
                isRenamingBoard = true
            }
            Button("Delete Board", role: .destructive) {
                Task { await viewModel.deleteActiveBoard() }
            }
            .disabled(!viewModel.canDeleteActiveBoard)
        } label: {
            Label(viewModel.activeBoardTitle, systemImage: "rectangle.stack")
        }
    }
}
