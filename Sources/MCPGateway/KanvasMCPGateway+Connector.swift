import Foundation

/// `canvas_connector_*` operations — the arrows linking two stickies on a card's canvas.
///
/// Like the sticky write ops (`+Canvas`), every write takes the owning `cardID` purely so it can
/// return that card's refreshed canvas, and drives the same UseCase layer as the app — validation
/// (edge / cap / routing / colour), domain rules, and persistence all apply. Every method parses
/// **all** ids before any use case runs, so a malformed argument can never surface as an error
/// *after* a write has already committed.
extension KanvasMCPGateway {

    /// Adds a connector from a sticky's edge. With `link.targetStickyID` it links that existing
    /// sticky; otherwise `dropFrame` grows a brand-new (empty) sticky at the drop point and links
    /// it — the same two paths as the app's grow gesture. `strokeColorHex` sets the stroke colour
    /// at creation; omit it (nil) to inherit the canvas-contrasting default (`#333`/`#ddd`), or
    /// restyle later via `editConnector`. The cap/routing/width still default (arrow/straight).
    public func addConnector(cardID: String, link: ConnectorLink, dropFrame: StickyFrame?,
                             strokeColorHex: String?) async throws -> String {
        let id = try uuid(cardID, "cardID")
        guard link.targetStickyID != nil || dropFrame != nil else {
            throw KanvasMCPError.missingConnectorTarget
        }
        let result = try await addConnectorUseCase.execute(AddConnectorRequest(
            cardID: id,
            sourceStickyID: try uuid(link.sourceStickyID, "sourceStickyID"),
            sourceEdge: link.sourceEdge,
            targetEdge: link.targetEdge,
            existingTargetStickyID: try link.targetStickyID.map { try uuid($0, "targetStickyID") },
            newStickyX: dropFrame?.x ?? 0, newStickyY: dropFrame?.y ?? 0,
            newStickyWidth: dropFrame?.width ?? 0, newStickyHeight: dropFrame?.height ?? 0,
            strokeColorHex: strokeColorHex
        ))
        return try await canvasJSON(result, cardID: id)
    }

    /// Applies the provided style fields, keeping the rest — one use case call, so the whole edit
    /// validates up front and commits as a single transaction/undo step (a mid-edit validation
    /// failure can never leave a partial restyle). An all-nil edit is rejected loudly so the model
    /// never mistakes a no-op for an applied change.
    public func editConnector(cardID: String, connectorID: String, style: ConnectorStyleEdit) async throws -> String {
        guard !style.isEmpty else { throw KanvasMCPError.emptyConnectorEdit }
        let id = try uuid(cardID, "cardID")
        let resolvedConnectorID = try uuid(connectorID, "connectorID")
        try await requireConnector(resolvedConnectorID, onCard: id)
        let result = try await setConnectorStyleUseCase.execute(SetConnectorStyleRequest(
            connectorID: resolvedConnectorID,
            cap: style.cap, routing: style.routing,
            strokeColorHex: style.strokeColorHex, strokeWidth: style.strokeWidth
        ))
        return try await canvasJSON(result, cardID: id)
    }

    /// Re-attaches a connector's endpoint(s). Provide `source` and/or `target`; an omitted side keeps
    /// its current endpoint. To move only an endpoint's edge, pass that side with the same sticky id
    /// and a new edge. An all-nil edit is rejected loudly (`emptyConnectorEdit`) so the model never
    /// mistakes a no-op for a change. A reconnect that would make both ends the same sticky is
    /// rejected by the domain (`connectorSelfLoop`). All ids are parsed before the use case runs.
    public func reconnectConnector(cardID: String, connectorID: String,
                                   source: ConnectorEndpointArg?,
                                   target: ConnectorEndpointArg?) async throws -> String {
        guard source != nil || target != nil else { throw KanvasMCPError.emptyConnectorEdit }
        let id = try uuid(cardID, "cardID")
        let resolvedConnectorID = try uuid(connectorID, "connectorID")
        let sourceStickyID = try source.map { try uuid($0.stickyID, "source.stickyID") }
        let targetStickyID = try target.map { try uuid($0.stickyID, "target.stickyID") }
        try await requireConnector(resolvedConnectorID, onCard: id)
        let result = try await reconnectConnectorUseCase.execute(ReconnectConnectorRequest(
            connectorID: resolvedConnectorID,
            sourceStickyID: sourceStickyID, sourceEdge: source?.edge,
            targetStickyID: targetStickyID, targetEdge: target?.edge
        ))
        return try await canvasJSON(result, cardID: id)
    }

    public func deleteConnector(cardID: String, connectorID: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let resolvedConnectorID = try uuid(connectorID, "connectorID")
        try await requireConnector(resolvedConnectorID, onCard: id)
        let result = try await deleteConnectorUseCase.execute(
            DeleteConnectorRequest(connectorID: resolvedConnectorID, cardID: id)
        )
        return try await canvasJSON(result, cardID: id)
    }

    /// Throws `notFound` when `connectorID` matches no connector **on this card**. The domain
    /// transforms now throw a board-global `OperationError.notFound` for a stale id (ticket
    /// F59ECB92), so this is no longer the *only* guard — but it is still card-scoped (the domain
    /// resolves a connector by id alone, without checking it belongs to `cardID`) and yields the
    /// typed MCP `notFound(kind: "Connector")` ahead of the domain backstop. Best-effort by nature
    /// (another process may mutate between check and commit); the echoed canvas stays authoritative.
    private func requireConnector(_ connectorID: UUID, onCard cardID: UUID) async throws {
        let detail = try await cardDetail(cardID: cardID)
        guard detail.connectors.contains(where: { $0.id == connectorID }) else {
            throw KanvasMCPError.notFound(kind: "Connector", id: connectorID.uuidString)
        }
    }
}
