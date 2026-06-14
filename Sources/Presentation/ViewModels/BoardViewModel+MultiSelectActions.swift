import Foundation

// MARK: - Multi-select group actions
//
// Group move and group delete over a multi-selection. The whole batch is applied as ONE domain
// mutation (one cross-process flock + read-modify-write, one undo entry) by the canvas-group use
// cases — not a per-item loop, which paid N writes and pushed N entries through the depth-5 undo
// ring, so ⌘Z could only half-rewind a large gesture (ticket 4FF14DCF). Routing each id to its kind
// (sticky / shape / image / connector) now lives in the Domain layer; the ViewModel just forwards
// the selection and publishes the single result.

extension BoardViewModel {

    /// Moves every item in `moves` to its new world centre. The canvas pre-computes each target
    /// (original centre + the shared, snapped drag delta), so relative layout is preserved. One
    /// batch mutation, one board publish.
    func moveSelected(_ moves: [CanvasDragMove]) async {
        // An empty batch would still open `mutate` (a no-op flock + write + undo entry) — short-circuit
        // it. Today's caller already guards (a group drag needs ≥2 members); this makes the VM robust
        // to a future caller that doesn't.
        guard let detail = selectedCardDetail, !moves.isEmpty else { return }
        let movements = moves.map {
            MoveCanvasGroupRequest.Movement(id: $0.id, positionX: $0.worldX, positionY: $0.worldY)
        }
        do {
            let response = try await groupUseCases.move.execute(
                MoveCanvasGroupRequest(movements: movements, cardID: detail.id))
            applyBoardMutation(response)
        } catch {
            self.error = error
        }
    }

    /// Deletes every id in `ids`. An already-gone item is tolerated in the Domain transform (it
    /// drops out of the batch), so this never surfaces a `notFound`. One batch mutation, one board
    /// publish, then the selection is cleared.
    func deleteSelected(ids: [UUID]) async {
        // Empty ids ⟺ empty selection (the caller passes `Array(selectedIDs)`), so short-circuiting
        // here also skips a redundant `clearSelection()` — and avoids a no-op `mutate` (flock + write
        // + undo entry) for a future caller that doesn't pre-guard.
        guard let detail = selectedCardDetail, !ids.isEmpty else { return }
        do {
            let response = try await groupUseCases.delete.execute(
                DeleteCanvasGroupRequest(ids: ids, cardID: detail.id))
            applyBoardMutation(response)
        } catch {
            self.error = error
        }
        clearSelection()
    }
}
