import Foundation

// MARK: - Connector mapping
//
// Kept in a same-file extension (encode + decode together) so the round-trip cannot drift, and split
// out of the primary file so each stays within the `file_length` budget.

extension BoardSnapshotMapper {

    /// Decodes connectors, **dropping any whose source or target sticky is absent** from
    /// `stickyIDs`. Such a connector can never draw (its endpoint has no edge to resolve) and is
    /// unreachable for selection/delete, so healing it on load prevents unreachable garbage from
    /// accumulating in the snapshot (a complement to the cascade delete in `StickyService.deleting`).
    /// Each drop, and each unknown cap/routing/edge raw value forced to its default, **records a
    /// recovery** so the latent write-back is observable. A *nil* cap/routing/stroke is a legitimate
    /// absence (a snapshot predating the field) — defaulted silently, never a recovery.
    static func connectorEntities(_ dtos: [ConnectorDTO], stickyIDs: Set<UUID>,
                                  into recoveries: inout [SnapshotRecovery]) -> [Connector] {
        var connectors: [Connector] = []
        for connector in dtos {
            guard stickyIDs.contains(connector.sourceStickyID),
                  stickyIDs.contains(connector.targetStickyID) else {
                recoveries.append(.connectorDropped(connectorID: connector.id,
                                                    sourceStickyID: connector.sourceStickyID,
                                                    targetStickyID: connector.targetStickyID))
                continue
            }
            let style = ConnectorStyle(
                cap: resolveOptional(connector.cap, fallback: ConnectorEndpointCap.arrow,
                                     into: &recoveries) { raw, fallback in
                    .connectorFieldCoerced(connectorID: connector.id, field: "cap",
                                           raw: raw, fallback: fallback)
                },
                routing: resolveOptional(connector.routing, fallback: ConnectorRouting.straight,
                                         into: &recoveries) { raw, fallback in
                    .connectorFieldCoerced(connectorID: connector.id, field: "routing",
                                           raw: raw, fallback: fallback)
                },
                // Pass the Optional through verbatim: a nil stroke (absent in the snapshot, or a
                // connector created with no explicit colour on a nil-background board) stays
                // **unset** so Presentation resolves it adaptively — it is not coalesced to a
                // `#000` sentinel, which would be indistinguishable from an explicit black.
                strokeColorHex: connector.strokeColorHex,
                strokeWidth: connector.strokeWidth ?? ConnectorStyle.defaultStrokeWidth
            )
            connectors.append(Connector(
                id: connector.id,
                cardID: connector.cardID,
                sourceStickyID: connector.sourceStickyID,
                sourceEdge: resolveRequired(connector.sourceEdge, fallback: CanvasEdge.right,
                                            into: &recoveries) { raw, fallback in
                    .connectorFieldCoerced(connectorID: connector.id, field: "sourceEdge",
                                           raw: raw, fallback: fallback)
                },
                targetStickyID: connector.targetStickyID,
                targetEdge: resolveRequired(connector.targetEdge, fallback: CanvasEdge.left,
                                            into: &recoveries) { raw, fallback in
                    .connectorFieldCoerced(connectorID: connector.id, field: "targetEdge",
                                           raw: raw, fallback: fallback)
                },
                style: style,
                // A waypoint exists only when both axes are present (the all-or-nothing contract); a
                // snapshot predating the field, or a half-written pair, decodes to nil (no waypoint —
                // the automatic route). A legitimate absence, defaulted silently, not a recovery.
                waypointOffset: waypointOffset(connector)
            ))
        }
        return connectors
    }

    /// Resolves an **optional** raw discriminator: `nil` ⇒ the default silently (legitimate absence);
    /// a present-but-unparseable value ⇒ the default **plus a recovery** (a coercion, a latent write).
    /// `onCoerce` receives the raw value and the fallback's raw value, and builds the recovery note.
    private static func resolveOptional<T: RawRepresentable>(
        _ raw: String?, fallback: T, into recoveries: inout [SnapshotRecovery],
        onCoerce: (_ raw: String, _ fallback: String) -> SnapshotRecovery
    ) -> T where T.RawValue == String {
        guard let raw else { return fallback }
        return resolveRequired(raw, fallback: fallback, into: &recoveries, onCoerce: onCoerce)
    }

    /// Resolves a **required** raw discriminator (the DTO field is non-optional, so a value is always
    /// present): an unparseable value is forced to `fallback` and **records a recovery** via `onCoerce`.
    private static func resolveRequired<T: RawRepresentable>(
        _ raw: String, fallback: T, into recoveries: inout [SnapshotRecovery],
        onCoerce: (_ raw: String, _ fallback: String) -> SnapshotRecovery
    ) -> T where T.RawValue == String {
        if let value = T(rawValue: raw) { return value }
        recoveries.append(onCoerce(raw, fallback.rawValue))
        return fallback
    }

    /// Resolves a connector's waypoint offset from the DTO's two axes: a `CanvasOffset` only when
    /// **both** are present (the all-or-nothing contract), else `nil` (no waypoint). A snapshot
    /// predating the field, or a half-written pair, is a legitimate absence — defaulted to `nil`
    /// silently, never a recovery (the connector simply draws its automatic route).
    private static func waypointOffset(_ dto: ConnectorDTO) -> CanvasOffset? {
        guard let dx = dto.waypointOffsetX, let dy = dto.waypointOffsetY else { return nil }
        return CanvasOffset(dx: dx, dy: dy)
    }

    static func connectorDTO(_ connector: Connector) -> ConnectorDTO {
        ConnectorDTO(
            id: connector.id,
            cardID: connector.cardID,
            sourceStickyID: connector.sourceStickyID,
            sourceEdge: connector.sourceEdge.rawValue,
            targetStickyID: connector.targetStickyID,
            targetEdge: connector.targetEdge.rawValue,
            cap: connector.style.cap.rawValue,
            routing: connector.style.routing.rawValue,
            strokeColorHex: connector.style.strokeColorHex,
            strokeWidth: connector.style.strokeWidth,
            waypointOffsetX: connector.waypointOffset?.dx,
            waypointOffsetY: connector.waypointOffset?.dy
        )
    }
}
