import Foundation

// MARK: - Sticky Actions

extension BoardViewModel {
    func addSticky(cardID: UUID, x: Double, y: Double, presetID: UUID) async {
        // Resolve the dragged palette preset to its absolute size + fill colour. An unknown id
        // (preset deleted mid-drag, or board not yet loaded) is a no-op — there is nothing to size.
        guard let preset = board?.settings.canvas.stickyPresets.first(where: { $0.id == presetID }) else { return }
        do {
            applyBoardMutation(try await stickyUseCases.add.execute(
                AddStickyRequest(
                    cardID: cardID, content: "New sticky",
                    positionX: x, positionY: y,
                    width: preset.width, height: preset.height,
                    fillColorHex: preset.colorHex
                )
            ))
        } catch {
            self.error = error
        }
    }

    /// ⌘C — remembers `id` as the paste source and resets the paste step counter. The single
    /// `CopiedCanvasItem` buffer holds at most one kind, so this replaces any copied text outright.
    func copySticky(id: UUID) {
        copiedItem = .sticky(id)
        pasteCount = 0
    }

    /// ⌘V — duplicates the copied sticky, stepped away from the source so repeated pastes don't
    /// stack, and selects the new copy. No-op if nothing was copied or the source is gone (e.g.
    /// deleted, or the user switched to another card's canvas).
    func pasteSticky() async {
        guard let id = copiedItem?.stickyID,
              let source = selectedCardDetail?.stickies.first(where: { $0.id == id }) else { return }
        // Captured to detect a card switch across the await: without it, resuming on a different
        // card would select a sticky on the wrong canvas.
        let cardID = selectedCardID
        pasteCount += 1
        let offset = 24.0 * Double(pasteCount)
        let existingIDs = Set(selectedCardDetail?.stickies.map(\.id) ?? [])
        do {
            // The duplicate returns the open card's refreshed detail (already containing the new
            // copy), adopted synchronously; awaiting still covers the rare fallback reload, so the
            // new copy is present when we diff for it below — the use case returns no new id.
            await applyBoardMutationAwaitingDetail(try await stickyUseCases.duplicate.execute(
                DuplicateStickyRequest(
                    stickyID: id,
                    positionX: source.positionX + offset,
                    positionY: source.positionY + offset
                )
            ))
            guard selectedCardID == cardID else { return }
            if let newID = selectedCardDetail?.stickies.first(where: { !existingIDs.contains($0.id) })?.id {
                // Route through the single-select entry, so the paste replaces the whole selection
                // (`selectedItems` becomes just the new copy) instead of leaving a prior multi-select
                // alongside it.
                select(stickyID: newID)
            }
        } catch {
            self.error = error
        }
    }

    func editSticky(id: UUID, content: String) async {
        do {
            applyBoardMutation(try await stickyUseCases.edit.execute(
                EditStickyRequest(stickyID: id, content: content)
            ))
        } catch {
            self.error = error
        }
    }

    func setStickyTextColor(id: UUID, colorHex: String) async {
        do {
            applyBoardMutation(try await stickyUseCases.setTextColor.execute(
                SetStickyTextColorRequest(stickyID: id, colorHex: colorHex)
            ))
        } catch {
            self.error = error
        }
    }

    /// Sets the sticky's background fill, or clears it (nil) back to the board's free/task default.
    func setStickyFillColor(id: UUID, colorHex: String?) async {
        do {
            applyBoardMutation(try await stickyUseCases.setFillColor.execute(
                SetStickyFillColorRequest(stickyID: id, fillColorHex: colorHex)
            ))
        } catch {
            self.error = error
        }
    }

    func setStickyFontSize(id: UUID, fontSize: Double) async {
        do {
            applyBoardMutation(try await stickyUseCases.setFontSize.execute(
                SetStickyFontSizeRequest(stickyID: id, fontSize: fontSize)
            ))
        } catch {
            self.error = error
        }
    }

    func moveSticky(id: UUID, x: Double, y: Double) async {
        do {
            applyBoardMutation(try await stickyUseCases.move.execute(
                MoveStickyRequest(stickyID: id, positionX: x, positionY: y)
            ))
        } catch {
            self.error = error
        }
    }

    /// `frame` is the sticky's new world-space rect (corner-anchored resize); the request sets its
    /// full frame — size plus centre — committed as one atomic mutation (not a pure resize).
    func setStickyFrame(id: UUID, frame: CGRect) async {
        do {
            applyBoardMutation(try await stickyUseCases.setFrame.execute(
                SetStickyFrameRequest(
                    stickyID: id,
                    width: Double(frame.width), height: Double(frame.height),
                    positionX: Double(frame.midX), positionY: Double(frame.midY)
                )
            ))
        } catch {
            self.error = error
        }
    }

    func bringStickyToFront(id: UUID) async {
        do {
            applyBoardMutation(try await stickyUseCases.bringToFront.execute(
                BringStickyToFrontRequest(stickyID: id)
            ))
        } catch {
            self.error = error
        }
    }

    func sendStickyToBack(id: UUID) async {
        do {
            applyBoardMutation(try await stickyUseCases.sendToBack.execute(
                SendStickyToBackRequest(stickyID: id)
            ))
        } catch {
            self.error = error
        }
    }

    func promoteSticky(id: UUID, toColumn: UUID) async {
        do {
            applyBoardMutation(try await stickyUseCases.promote.execute(
                PromoteStickyRequest(stickyID: id, toColumnID: toColumn)
            ))
        } catch {
            self.error = error
        }
    }

    func demoteSticky(id: UUID) async {
        do {
            applyBoardMutation(try await stickyUseCases.demote.execute(DemoteStickyRequest(stickyID: id)))
        } catch {
            self.error = error
        }
    }

    func deleteSticky(id: UUID) async {
        await applyCanvasDelete(id: id) {
            try await stickyUseCases.delete.execute(DeleteStickyRequest(stickyID: id, cardID: selectedCardID))
        }
    }

    /// Reverts the most recent board change (move / resize / edit / create / delete).
    ///
    /// Three outcomes (see `UndoResponse`): `.restored` republishes the reverted board;
    /// `.nothingToUndo` (empty history) is a silent no-op, the standard ⌘Z-with-nothing-left
    /// behaviour; `.abortedExternalEdit` surfaces a one-shot `notice` *and* reloads — undo was
    /// blocked because another process (the MCP server) edited the board since the mutation, so the
    /// ⌘Z did nothing for a reason the user cannot otherwise see. The reload shows the divergent
    /// on-disk state immediately and deterministically: `BoardStoreWatcher` would also surface it,
    /// but it is debounced/coalescing, leaving a window where the notice contradicts a stale canvas.
    ///
    /// Canvas-wide, **not** sticky-specific: `undo` reverts the latest mutation of *any* canvas
    /// element (sticky / shape / connector / image). Injected directly into `BoardViewModel` (not the
    /// sticky bundle) for that reason; `+StickyActions` is just its sole consumer.
    func undo() async {
        do {
            switch try await undoUseCase.execute(UndoRequest()) {
            case .restored(let board):
                applyBoard(board)
            case .nothingToUndo:
                break
            case .abortedExternalEdit:
                notice = UserNotice(
                    title: "Undo Skipped",
                    message: "The board was changed externally — undo was skipped to avoid overwriting it."
                )
                await load()
            }
        } catch {
            self.error = error
        }
    }
}
