import Foundation

final class ConnectorService: ConnectorServiceProtocol, Sendable {
    private let repository: any BoardRepositoryProtocol
    /// Composing a sibling Service's **pure** transform inside one `mutate` so "drop on empty →
    /// create the target sticky **and** the connector" is a single undo step. This is the one
    /// sanctioned Service→Service dependency (see `arch-domain-services.md` → "Multi-entity
    /// composition"); only the pure `adding` transform is used, never another mutate.
    private let stickyService: any StickyServiceProtocol

    init(repository: any BoardRepositoryProtocol, stickyService: any StickyServiceProtocol) {
        self.repository = repository
        self.stickyService = stickyService
    }

    // MARK: Imperative verbs (own the mutate boundary)

    /// Adds a connector. When `seed.existingTargetStickyID` is nil, a new free sticky is created at
    /// `seed.newStickyPlacement` and used as the target — both the sticky and the connector commit in
    /// one mutation (one undo). `seed.strokeColorHex` is the caller's explicit stroke colour, or `nil`
    /// to inherit the canvas-contrasting default (see `adding`).
    func add(cardID: Card.ID, seed: ConnectorSeed) async throws -> BoardState {
        try await repository.mutate { state in
            var working = state
            let targetID: Sticky.ID
            if let existing = seed.existingTargetStickyID {
                targetID = existing
            } else {
                let existingIDs = Set(working.stickies.map(\.id))
                working = self.stickyService.adding(
                    content: "", placement: seed.newStickyPlacement, toCardCanvas: cardID, in: working
                )
                // `adding` always appends exactly one sticky, so the diff is non-empty; throw loudly
                // rather than silently dropping the gesture if that invariant is ever broken.
                guard let newID = working.stickies.first(where: { !existingIDs.contains($0.id) })?.id else {
                    throw OperationError.inconsistentState(reason: "new sticky not found after adding")
                }
                targetID = newID
            }
            let endpoints = ConnectorEndpoints(
                sourceStickyID: seed.sourceStickyID, sourceEdge: seed.sourceEdge,
                targetStickyID: targetID, targetEdge: seed.targetEdge
            )
            return try self.adding(endpoints: endpoints, strokeColorHex: seed.strokeColorHex,
                                   toCardCanvas: cardID, in: working)
        }
    }

    func setCap(id: Connector.ID, cap: ConnectorEndpointCap) async throws -> BoardState {
        try await repository.mutate { state in try self.settingCap(id: id, cap: cap, in: state) }
    }

    func setRouting(id: Connector.ID, routing: ConnectorRouting) async throws -> BoardState {
        try await repository.mutate { state in try self.settingRouting(id: id, routing: routing, in: state) }
    }

    func setStrokeColor(id: Connector.ID, colorHex: String?) async throws -> BoardState {
        try await repository.mutate { state in try self.settingStrokeColor(id: id, colorHex: colorHex, in: state) }
    }

    func setStrokeWidth(id: Connector.ID, width: Double) async throws -> BoardState {
        try await repository.mutate { state in try self.settingStrokeWidth(id: id, width: width, in: state) }
    }

    func setWaypoint(id: Connector.ID, offset: CanvasOffset?) async throws -> BoardState {
        try await repository.mutate { state in try self.settingWaypoint(id: id, offset: offset, in: state) }
    }

    /// Applies any subset of cap / routing / stroke colour / stroke width as one mutation, so a
    /// multi-field restyle (e.g. the MCP `canvas_connector_edit` tool) is a single undo step.
    func setStyle(id: Connector.ID, change: ConnectorStyleChange) async throws -> BoardState {
        try await repository.mutate { state in
            var working = state
            if let cap = change.cap { working = try self.settingCap(id: id, cap: cap, in: working) }
            if let routing = change.routing {
                working = try self.settingRouting(id: id, routing: routing, in: working)
            }
            if let strokeColorHex = change.strokeColorHex {
                working = try self.settingStrokeColor(id: id, colorHex: strokeColorHex, in: working)
            }
            if let strokeWidth = change.strokeWidth {
                working = try self.settingStrokeWidth(id: id, width: strokeWidth, in: working)
            }
            return working
        }
    }

    /// Re-attaches a connector's endpoint(s) in one mutation (one undo step). Like `setStyle`, the
    /// self-loop rule and the new-sticky existence checks all run inside the pure transform before
    /// anything commits.
    func reconnect(id: Connector.ID,
                   source: ConnectorEndpoint?, target: ConnectorEndpoint?) async throws -> BoardState {
        try await repository.mutate { state in
            try self.reconnecting(id: id, source: source, target: target, in: state)
        }
    }

    func delete(id: Connector.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.deleting(id: id, from: state) }
    }

    // MARK: Pure transforms

    func adding(endpoints: ConnectorEndpoints, strokeColorHex: String?,
                toCardCanvas cardID: Card.ID, in state: BoardState) throws -> BoardState {
        // Reject a self-loop before appending — same rule as `reconnecting`. The UI grow gesture
        // avoids this structurally (it never targets the source sticky), so this guards the MCP
        // `canvas_connector_add` path, which used to slip a self-linking connector through unchecked.
        guard endpoints.sourceStickyID != endpoints.targetStickyID else {
            throw ValidationError.connectorSelfLoop
        }
        var state = state
        let connector = Connector(
            cardID: cardID,
            sourceStickyID: endpoints.sourceStickyID,
            sourceEdge: endpoints.sourceEdge,
            targetStickyID: endpoints.targetStickyID,
            targetEdge: endpoints.targetEdge,
            style: Self.resolvedStrokeStyle(requestedStrokeColorHex: strokeColorHex,
                                            onBackground: state.settings.global.backgroundColorHex)
        )
        state.connectors.append(connector)
        return state
    }

    /// Resolves a new connector's stroke colour from whether the caller *specified* one — not from
    /// a sentinel value match. This mirrors `StickyService.adding`, which gates on `fillColorHex`
    /// being present (`.map`) rather than equal to a default, so an explicitly-chosen colour — even
    /// pure black — is never mistaken for "unset" and silently overwritten.
    ///
    /// - A caller-specified `requestedStrokeColorHex` is honoured verbatim.
    /// - No specified colour ⇒ auto-contrast against the canvas background (`#333` light / `#ddd`
    ///   dark) via `ContrastColor`, the single Domain source — so a default connector stays visible.
    ///   Baked at creation, not recomputed on render, so a later light→dark `backgroundColorHex`
    ///   flip leaves existing default connectors on their original pick (now lower-contrast) until
    ///   re-created — the same trade-off as sticky text.
    /// - No specified colour **and** no configured `backgroundColorHex` ⇒ stroke stays **unset**
    ///   (`nil`, via `.default`): the fallback canvas is AppKit's dynamic `windowBackgroundColor`,
    ///   whose hex Domain cannot resolve, so it does not guess light/dark. Presentation resolves that
    ///   unset stroke adaptively at draw time. Storing `nil` rather than a `#000` sentinel is what
    ///   lets an *explicit* black (the first branch) survive distinct from "never set" — see
    ///   `ConnectorStyle.strokeColorHex`.
    private static func resolvedStrokeStyle(requestedStrokeColorHex: String?,
                                            onBackground backgroundHex: String?) -> ConnectorStyle {
        if let requestedStrokeColorHex {
            return ConnectorStyle(strokeColorHex: requestedStrokeColorHex)
        }
        guard let backgroundHex else { return .default }
        return ConnectorStyle(strokeColorHex: ContrastColor.readableHex(onBackground: backgroundHex))
    }

    func settingCap(id: Connector.ID, cap: ConnectorEndpointCap, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.connectors, entityKind: "Connector")
        state.connectors[idx].style.cap = cap
        return state
    }

    func settingRouting(id: Connector.ID, routing: ConnectorRouting, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.connectors, entityKind: "Connector")
        state.connectors[idx].style.routing = routing
        return state
    }

    func settingStrokeColor(id: Connector.ID, colorHex: String?, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.connectors, entityKind: "Connector")
        // `nil` clears the stroke back to unset, so the connector renders adaptively again (the Clear
        // affordance in the toolbar); a non-nil hex is an explicit pick stored verbatim.
        state.connectors[idx].style.strokeColorHex = colorHex
        return state
    }

    func settingStrokeWidth(id: Connector.ID, width: Double, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.connectors, entityKind: "Connector")
        // Re-construct through the initializer so the width is clamped to the valid range.
        let current = state.connectors[idx].style
        state.connectors[idx].style = ConnectorStyle(
            cap: current.cap,
            routing: current.routing,
            strokeColorHex: current.strokeColorHex,
            strokeWidth: width
        )
        return state
    }

    /// Sets (or clears, with `nil`) a connector's waypoint offset — the central deformation handle's
    /// shift from the midpoint of the two endpoint edge midpoints. `nil` restores the automatic
    /// (un-deformed) route. Routing-agnostic at the domain level: the offset is stored on any
    /// connector, and Presentation ignores it for `straight` (no handle is shown there).
    func settingWaypoint(id: Connector.ID, offset: CanvasOffset?, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.connectors, entityKind: "Connector")
        state.connectors[idx].waypointOffset = offset
        return state
    }

    /// Moves a connector's endpoint(s). Resolution order (validate fully, then one write):
    /// 1. Resolve the connector by id — `OperationError.notFound` if absent.
    /// 2. For each provided side, the new sticky must live on the connector's card canvas (`cardID`)
    ///    — `OperationError.notFound` otherwise. A `nil` side keeps the current endpoint.
    /// 3. The applied result must not be a self-loop (`sourceStickyID == targetStickyID`) —
    ///    `ValidationError.connectorSelfLoop`. (Moving a side to a different edge of the *same*
    ///    sticky is fine; it is just an edge change.)
    func reconnecting(id: Connector.ID, source: ConnectorEndpoint?, target: ConnectorEndpoint?,
                      in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.connectors, entityKind: "Connector")
        let cardID = state.connectors[idx].cardID

        // Resolve the post-reconnect endpoints, validating each touched side's sticky exists on the
        // connector's card before any write — a stale/foreign sticky id is `notFound`, not a no-op.
        let newSourceStickyID = source?.stickyID ?? state.connectors[idx].sourceStickyID
        let newTargetStickyID = target?.stickyID ?? state.connectors[idx].targetStickyID
        if source != nil {
            try requireSticky(newSourceStickyID, onCard: cardID, in: state)
        }
        if target != nil {
            try requireSticky(newTargetStickyID, onCard: cardID, in: state)
        }
        guard newSourceStickyID != newTargetStickyID else {
            throw ValidationError.connectorSelfLoop
        }

        if let source {
            state.connectors[idx].sourceStickyID = source.stickyID
            state.connectors[idx].sourceEdge = source.edge
        }
        if let target {
            state.connectors[idx].targetStickyID = target.stickyID
            state.connectors[idx].targetEdge = target.edge
        }
        return state
    }

    /// Throws `OperationError.notFound` unless a sticky `stickyID` exists on `cardID`'s canvas. The
    /// connector's endpoints are constrained to its own card, so a reconnect target must be local.
    private func requireSticky(_ stickyID: Sticky.ID, onCard cardID: Card.ID, in state: BoardState) throws {
        guard state.stickies.contains(where: { $0.id == stickyID && $0.cardID == cardID }) else {
            throw OperationError.notFound(entityKind: "Sticky", id: stickyID)
        }
    }

    func deleting(id: Connector.ID, from state: BoardState) throws -> BoardState {
        guard state.connectors.contains(where: { $0.id == id }) else {
            throw OperationError.notFound(entityKind: "Connector", id: id)
        }
        var state = state
        state.connectors.removeAll { $0.id == id }
        return state
    }
}
