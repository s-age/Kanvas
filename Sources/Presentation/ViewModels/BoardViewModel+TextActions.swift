import Foundation

// MARK: - Free-text Actions

extension BoardViewModel {

    /// Default on-canvas size of a palette-dropped text (matches `TextSize.default`). Centre-anchored
    /// at the drop point.
    private static let defaultTextWidth: Double = 200
    private static let defaultTextHeight: Double = 80

    /// Creates an empty free-text object at `(x, y)` and asks the canvas to begin editing it once it
    /// appears (so a dropped text is immediately typeable — ticket 7C1D6316 決め事 3). The new text's
    /// id is the one not present before the add; an empty text the user dismisses without typing is
    /// auto-deleted on edit-commit.
    func addText(cardID: UUID, x: Double, y: Double) async {
        let priorIDs = Set((selectedCardDetail?.texts ?? []).map(\.id))
        do {
            let response = try await textUseCases.add.execute(AddTextRequest(
                cardID: cardID, content: "",
                positionX: x, positionY: y,
                width: Self.defaultTextWidth, height: Self.defaultTextHeight
            ))
            // Adopt the result synchronously so the new text is in `selectedCardDetail` for the diff
            // and for the canvas's editor lookup on the next `update`.
            await applyBoardMutationAwaitingDetail(response)
            if let newID = (selectedCardDetail?.texts ?? []).map(\.id).first(where: { !priorIDs.contains($0) }) {
                select(textID: newID)
                requestTextEdit(id: newID)
            }
        } catch {
            self.error = error
        }
    }

    /// ⌘C — remembers `id` as the paste source and resets the paste step counter. The single
    /// `CopiedCanvasItem` buffer holds at most one kind, so this replaces any copied sticky outright.
    func copyText(id: UUID) {
        copiedItem = .text(id)
        pasteCount = 0
    }

    /// ⌘V — duplicates the copied text, stepped away from the source so repeated pastes don't stack,
    /// and selects the new copy. No-op if nothing was copied or the source is gone (deleted, or the
    /// user switched to another card's canvas). Mirrors `pasteSticky`.
    func pasteText() async {
        guard let id = copiedItem?.textID,
              let source = (selectedCardDetail?.texts ?? []).first(where: { $0.id == id }) else { return }
        // Captured to detect a card switch across the await: resuming on a different card would
        // otherwise select a text on the wrong canvas.
        let cardID = selectedCardID
        pasteCount += 1
        let offset = 24.0 * Double(pasteCount)
        let existingIDs = Set((selectedCardDetail?.texts ?? []).map(\.id))
        do {
            await applyBoardMutationAwaitingDetail(try await textUseCases.duplicate.execute(
                DuplicateTextRequest(
                    textID: id,
                    positionX: source.positionX + offset,
                    positionY: source.positionY + offset
                )
            ))
            guard selectedCardID == cardID else { return }
            if let newID = (selectedCardDetail?.texts ?? []).map(\.id).first(where: { !existingIDs.contains($0) }) {
                select(textID: newID)
            }
        } catch {
            self.error = error
        }
    }

    func editText(id: UUID, content: String) async {
        do {
            applyBoardMutation(try await textUseCases.edit.execute(
                EditTextRequest(textID: id, content: content)
            ))
        } catch {
            self.error = error
        }
    }

    func moveText(id: UUID, x: Double, y: Double) async {
        do {
            applyBoardMutation(try await textUseCases.move.execute(
                MoveTextRequest(textID: id, positionX: x, positionY: y)
            ))
        } catch {
            self.error = error
        }
    }

    /// `frame` is the text's new world-space box; size + centre commit as one atomic mutation.
    func setTextFrame(id: UUID, frame: CGRect) async {
        do {
            applyBoardMutation(try await textUseCases.resize.execute(
                ResizeTextRequest(
                    textID: id,
                    width: Double(frame.width), height: Double(frame.height),
                    positionX: Double(frame.midX), positionY: Double(frame.midY)
                )
            ))
        } catch {
            self.error = error
        }
    }

    func setTextColor(id: UUID, colorHex: String) async {
        do {
            applyBoardMutation(try await textUseCases.setColor.execute(
                SetTextColorRequest(textID: id, colorHex: colorHex)
            ))
        } catch {
            self.error = error
        }
    }

    func setTextFontSize(id: UUID, fontSize: Double) async {
        do {
            applyBoardMutation(try await textUseCases.setFontSize.execute(
                SetTextFontSizeRequest(textID: id, fontSize: fontSize)
            ))
        } catch {
            self.error = error
        }
    }

    func bringTextToFront(id: UUID) async {
        do {
            applyBoardMutation(try await textUseCases.bringToFront.execute(BringTextToFrontRequest(textID: id)))
        } catch {
            self.error = error
        }
    }

    func sendTextToBack(id: UUID) async {
        do {
            applyBoardMutation(try await textUseCases.sendToBack.execute(SendTextToBackRequest(textID: id)))
        } catch {
            self.error = error
        }
    }

    func deleteText(id: UUID) async {
        await applyCanvasDelete(id: id) {
            try await textUseCases.delete.execute(DeleteTextRequest(textID: id, cardID: selectedCardID))
        }
    }
}
