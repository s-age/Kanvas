import SwiftUI

// MARK: - Editing Lifecycle

// These helpers drive the view's editing state (editingTarget / editingTitle / focusedField).
// Same-type cross-file extension, so members are `internal` (the minimum that compiles for calls
// from KanbanBoardView.swift's body) rather than `private`.
extension KanbanBoardView {

    func cancelEditing() {
        editingTarget = nil
        focusedField = nil
    }

    /// Commits whichever rename is currently active (if any). Called when focus leaves the
    /// field through a path that does not change `focusedField` — a background/empty-area
    /// click, or selecting another card. Returns the persistence task so a caller that must
    /// serialize against the write (see `beginEditingNewCard`) can `await` it; sync callers
    /// ignore it (`@discardableResult`).
    @discardableResult
    func commitActiveEdit() -> Task<Void, Never>? {
        switch editingTarget {
        case .card(let id): return commitCardRename(id)
        case .column(let id): return commitColumnRename(id)
        case nil: return nil
        }
    }

    /// Creates a card and immediately drops into rename mode on it, mirroring how
    /// the context-menu "Rename Card" begins editing (focus is taken by the editing
    /// row's `.onAppear`).
    func beginEditingNewCard(in columnID: UUID) async {
        // Commit any in-progress rename and wait for it to *persist* before adding, so the
        // two writes are strictly serialized instead of racing. The repository's `mutate` is
        // already an atomic read-modify-write (so today's writes don't actually lose updates),
        // but awaiting here keeps the ordering explicit and correct even if `mutate` ever
        // becomes truly async — and removes the silent-loss path on the previous card's title.
        await commitActiveEdit()?.value
        guard let newCardID = await viewModel.addCard(title: "New Card", columnID: columnID) else { return }
        editingTitle = "New Card"
        editingTarget = .card(newCardID)
    }

    @discardableResult
    func commitCardRename(_ cardID: UUID) -> Task<Void, Never>? {
        // Guard makes commit idempotent: focus-loss and Enter (onCommit) may both fire.
        guard editingTarget == .card(cardID) else { return nil }
        let title = editingTitle
        cancelEditing()
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Task {
            await viewModel.editCard(EditCardRequest(cardID: cardID, title: title))
        }
    }

    @discardableResult
    func commitColumnRename(_ columnID: UUID) -> Task<Void, Never>? {
        guard editingTarget == .column(columnID) else { return nil }
        let title = editingTitle
        cancelEditing()
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Task {
            await viewModel.renameColumn(id: columnID, title: title)
        }
    }
}
