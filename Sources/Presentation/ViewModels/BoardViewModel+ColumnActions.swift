import Foundation

// Column CRUD — split into its own file so `BoardViewModel.swift` stays within the file-length
// budget.

extension BoardViewModel {

    func addColumn(title: String) async {
        do {
            applyBoard(try await kanbanUseCases.addColumn.execute(AddColumnRequest(title: title)))
        } catch {
            self.error = error
        }
    }

    func renameColumn(id: UUID, title: String) async {
        do {
            applyBoard(try await kanbanUseCases.renameColumn.execute(
                RenameColumnRequest(columnID: id, title: title)
            ))
        } catch {
            self.error = error
        }
    }

    func setCompletionColumn(id: UUID, isCompletion: Bool) async {
        do {
            applyBoard(try await kanbanUseCases.setCompletionColumn.execute(
                SetCompletionColumnRequest(columnID: id, isCompletion: isCompletion)
            ))
        } catch {
            self.error = error
        }
    }

    func reorderColumn(id: UUID, before beforeColumnID: UUID?) async {
        do {
            applyBoard(try await kanbanUseCases.reorderColumn.execute(
                ReorderColumnRequest(columnID: id, beforeColumnID: beforeColumnID)
            ))
        } catch {
            self.error = error
        }
    }

    func deleteColumn(id: UUID) async {
        do {
            applyBoard(try await kanbanUseCases.deleteColumn.execute(DeleteColumnRequest(columnID: id)))
        } catch {
            self.error = error
        }
    }
}
