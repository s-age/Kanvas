import Foundation

// MARK: - Label Actions
//
// The app-wide sticky-label registry (create / edit / delete) plus per-sticky assignment.
// Every mutation returns the whole board; `applyBoard` republishes it and refreshes the
// selected card's detail so the canvas pills and the manager panel reflect the change.

extension BoardViewModel {

    /// Opens the label-management panel targeting `stickyID` for assignment. Setting the target
    /// is what opens the panel (`isLabelManagerPresented` derives from it).
    func openLabelManager(stickyID: UUID) {
        labelManagerStickyID = stickyID
    }

    func closeLabelManager() {
        labelManagerStickyID = nil
    }

    func addLabel(name: String, colorHex: String) async {
        do {
            applyBoard(try await labelUseCases.add.execute(AddLabelRequest(name: name, colorHex: colorHex)))
        } catch {
            self.error = error
        }
    }

    func editLabel(id: UUID, name: String, colorHex: String) async {
        do {
            applyBoard(try await labelUseCases.edit.execute(
                EditLabelRequest(labelID: id, name: name, colorHex: colorHex)
            ))
        } catch {
            self.error = error
        }
    }

    func deleteLabel(id: UUID) async {
        do {
            applyBoard(try await labelUseCases.delete.execute(DeleteLabelRequest(labelID: id)))
        } catch {
            self.error = error
        }
    }

    /// Toggles `labelID` on the sticky — assigns it when absent, removes it when already tagged.
    func toggleStickyLabel(stickyID: UUID, labelID: UUID) async {
        do {
            applyBoardMutation(try await labelUseCases.toggle.execute(
                ToggleStickyLabelRequest(stickyID: stickyID, labelID: labelID)
            ))
        } catch {
            self.error = error
        }
    }
}
