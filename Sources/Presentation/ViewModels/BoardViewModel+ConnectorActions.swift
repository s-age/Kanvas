import Foundation

// MARK: - Connector Actions

extension BoardViewModel {
    /// Grows a connector from the `grow` gesture. When `existingTargetStickyID` is non-nil it links
    /// that sticky; otherwise a new sticky is created at the drop point and linked.
    func addConnector(cardID: UUID, grow: ConnectorGrowGesture) async {
        // A grown sticky uses the board's middle palette preset for its size (or a 200×150 default
        // when no preset is configured); the domain re-clamps on creation. It is not a palette
        // drag, so it takes no preset fill colour — the board's free-sticky default applies.
        let presets = board?.settings.canvas.stickyPresets ?? []
        let sizePreset = presets.isEmpty ? nil : presets[presets.count / 2]
        let width = sizePreset?.width ?? 200
        let height = sizePreset?.height ?? 150
        do {
            applyBoardMutation(try await connectorUseCases.add.execute(
                AddConnectorRequest(
                    cardID: cardID,
                    sourceStickyID: grow.sourceStickyID, sourceEdge: grow.sourceEdge,
                    targetEdge: grow.targetEdge,
                    existingTargetStickyID: grow.existingTargetStickyID,
                    newStickyX: grow.dropWorldX, newStickyY: grow.dropWorldY,
                    newStickyWidth: width, newStickyHeight: height
                )
            ))
        } catch {
            self.error = error
        }
    }

    /// Re-attaches the dragged end of a connector to a different sticky / edge. Only the side the
    /// gesture moved is filled in the request; the other endpoint is left untouched. The domain
    /// rejects a resulting self-loop (the canvas already snaps the gesture back in that case, but
    /// the guard is authoritative). The connector is resolved by `gesture.connectorID` alone, so —
    /// unlike the card-scoped `addConnector` — this takes no `cardID`.
    func reconnectConnector(gesture: ConnectorReconnectGesture) async {
        let request: ReconnectConnectorRequest
        switch gesture.side {
        case .source:
            request = ReconnectConnectorRequest(
                connectorID: gesture.connectorID,
                sourceStickyID: gesture.newStickyID, sourceEdge: gesture.newEdge
            )
        case .target:
            request = ReconnectConnectorRequest(
                connectorID: gesture.connectorID,
                targetStickyID: gesture.newStickyID, targetEdge: gesture.newEdge
            )
        }
        do {
            applyBoardMutation(try await connectorUseCases.reconnect.execute(request))
        } catch {
            self.error = error
        }
    }

    /// Sets a connector's waypoint (central deformation) offset — the dragged handle's shift, in
    /// world units, from the midpoint of its two endpoint edge midpoints. Resolved by id alone (like
    /// `reconnectConnector`), so it takes no `cardID`.
    func setConnectorWaypoint(id: UUID, offsetX: Double, offsetY: Double) async {
        do {
            applyBoardMutation(try await connectorUseCases.setWaypoint.execute(
                SetConnectorWaypointRequest(connectorID: id, offsetX: offsetX, offsetY: offsetY)
            ))
        } catch {
            self.error = error
        }
    }

    func setConnectorCap(id: UUID, cap: String) async {
        do {
            applyBoardMutation(try await connectorUseCases.setCap.execute(
                SetConnectorCapRequest(connectorID: id, cap: cap)
            ))
        } catch {
            self.error = error
        }
    }

    func setConnectorRouting(id: UUID, routing: String) async {
        do {
            applyBoardMutation(try await connectorUseCases.setRouting.execute(
                SetConnectorRoutingRequest(connectorID: id, routing: routing)
            ))
        } catch {
            self.error = error
        }
    }

    /// `colorHex == nil` clears the stroke back to unset (adaptive at draw time); a hex sets it.
    func setConnectorStrokeColor(id: UUID, colorHex: String?) async {
        do {
            applyBoardMutation(try await connectorUseCases.setStrokeColor.execute(
                SetConnectorStrokeColorRequest(connectorID: id, colorHex: colorHex)
            ))
        } catch {
            self.error = error
        }
    }

    func setConnectorStrokeWidth(id: UUID, width: Double) async {
        do {
            applyBoardMutation(try await connectorUseCases.setStrokeWidth.execute(
                SetConnectorStrokeWidthRequest(connectorID: id, width: width)
            ))
        } catch {
            self.error = error
        }
    }

    func deleteConnector(id: UUID) async {
        await applyCanvasDelete(id: id) {
            try await connectorUseCases.delete.execute(DeleteConnectorRequest(connectorID: id, cardID: selectedCardID))
        }
    }
}
