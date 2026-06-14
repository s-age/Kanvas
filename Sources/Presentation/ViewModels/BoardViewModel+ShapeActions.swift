import Foundation

// MARK: - Shape Actions

extension BoardViewModel {
    func addShape(cardID: UUID, draft: ShapeDraft) async {
        do {
            applyBoardMutation(try await shapeUseCases.add.execute(
                AddShapeRequest(
                    cardID: cardID, kind: draft.kind, topology: draft.topology.rawValue,
                    positionX: draft.worldX, positionY: draft.worldY,
                    width: draft.defaultWidth, height: draft.defaultHeight
                )
            ))
        } catch {
            self.error = error
        }
    }

    func moveShape(id: UUID, x: Double, y: Double) async {
        do {
            applyBoardMutation(try await shapeUseCases.move.execute(
                MoveShapeRequest(shapeID: id, positionX: x, positionY: y)
            ))
        } catch {
            self.error = error
        }
    }

    /// `frame` is the shape's new world-space bounding rect; size + centre commit as one atomic
    /// mutation. `lineRising` is supplied only when a line's endpoint was dragged (which diagonal
    /// the segment now runs along); `nil` for rectangle/ellipse corner resizes.
    func resizeShape(id: UUID, frame: CGRect, lineRising: Bool? = nil) async {
        do {
            applyBoardMutation(try await shapeUseCases.resize.execute(
                ResizeShapeRequest(
                    shapeID: id,
                    width: Double(frame.width), height: Double(frame.height),
                    positionX: Double(frame.midX), positionY: Double(frame.midY),
                    lineRising: lineRising
                )
            ))
        } catch {
            self.error = error
        }
    }

    func setShapeStrokeColor(id: UUID, colorHex: String) async {
        do {
            applyBoardMutation(try await shapeUseCases.setStrokeColor.execute(
                SetShapeStrokeColorRequest(shapeID: id, colorHex: colorHex)
            ))
        } catch {
            self.error = error
        }
    }

    /// `colorHex == nil` clears the fill (stroke-only shape).
    func setShapeFillColor(id: UUID, colorHex: String?) async {
        do {
            applyBoardMutation(try await shapeUseCases.setFillColor.execute(
                SetShapeFillColorRequest(shapeID: id, colorHex: colorHex)
            ))
        } catch {
            self.error = error
        }
    }

    func setShapeStrokeWidth(id: UUID, width: Double) async {
        do {
            applyBoardMutation(try await shapeUseCases.setStrokeWidth.execute(
                SetShapeStrokeWidthRequest(shapeID: id, width: width)
            ))
        } catch {
            self.error = error
        }
    }

    func bringShapeToFront(id: UUID) async {
        do {
            applyBoardMutation(try await shapeUseCases.bringToFront.execute(BringShapeToFrontRequest(shapeID: id)))
        } catch {
            self.error = error
        }
    }

    func sendShapeToBack(id: UUID) async {
        do {
            applyBoardMutation(try await shapeUseCases.sendToBack.execute(SendShapeToBackRequest(shapeID: id)))
        } catch {
            self.error = error
        }
    }

    func deleteShape(id: UUID) async {
        await applyCanvasDelete(id: id) {
            try await shapeUseCases.delete.execute(DeleteShapeRequest(shapeID: id, cardID: selectedCardID))
        }
    }
}
