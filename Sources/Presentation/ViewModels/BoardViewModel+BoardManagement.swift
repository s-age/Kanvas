import Foundation

// Multi-board CRUD + switching, split into its own file so `BoardViewModel.swift` stays within the
// file-length budget. Switching/creating/deleting a board swaps the whole canvas, so each clears
// `selectedCardID` (cards belong to the previous board) before publishing the new board. Publishing
// the picker list goes through `applyBoardList` (in the main file, which owns the `private(set)` state).

extension BoardViewModel {

    /// Whether deleting is allowed — never delete the last remaining board.
    var canDeleteActiveBoard: Bool { boards.count > 1 }

    /// The active board's title, for the picker label. The title exists in two read models — the
    /// catalog-backed `boards` summary list and the active `board` response — so this resolves the
    /// precedence in one place instead of leaving callers to pick: the **catalog `boards` list is the
    /// rename source of truth** (`renameActiveBoard` updates only it), so it wins, letting a rename
    /// surface without reloading the whole board. `board.board.title` is the fallback only for the
    /// brief window after a board switch when the new `board` has published but `loadBoards()` has
    /// not yet refreshed `boards` — without it the picker label would flash empty. Empty string is
    /// the last resort before any board has loaded.
    var activeBoardTitle: String {
        boards.first { $0.id == activeBoardID }?.title ?? board?.board.title ?? ""
    }

    func loadBoards() async {
        do {
            applyBoardList(try await managementUseCases.list.execute(ListBoardsRequest()))
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }

    func switchBoard(to id: UUID) async {
        guard id != activeBoardID else { return }
        do {
            // Clear the selection only after the switch succeeds — on a thrown error the previous
            // board (and its selection) stays intact rather than half-cleared.
            let response = try await managementUseCases.switchBoard.execute(SwitchBoardRequest(boardID: id))
            selectedCardID = nil
            // Search scope is the active board, so a switch clears the field + filter.
            clearSearch()
            applyBoard(response)
            await loadBoards()
        } catch {
            self.error = error
        }
    }

    func addBoard(title: String) async {
        do {
            let response = try await managementUseCases.add.execute(AddBoardRequest(title: title))
            selectedCardID = nil
            clearSearch()
            applyBoard(response)
            await loadBoards()
        } catch {
            self.error = error
        }
    }

    func renameActiveBoard(title: String) async {
        guard let id = activeBoardID else { return }
        do {
            applyBoardList(try await managementUseCases.rename.execute(
                RenameBoardRequest(boardID: id, title: title)
            ))
        } catch {
            self.error = error
        }
    }

    func deleteActiveBoard() async {
        guard let id = activeBoardID, canDeleteActiveBoard else { return }
        do {
            let response = try await managementUseCases.delete.execute(DeleteBoardRequest(boardID: id))
            selectedCardID = nil
            clearSearch()
            applyBoard(response)
            await loadBoards()
        } catch {
            self.error = error
        }
    }
}
