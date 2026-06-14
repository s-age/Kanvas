import Foundation

/// Edit-fields bag for `ConnectorService.setStyle` — a partial restyle where each field is Optional
/// to express "leave unchanged" (`nil`) versus "set to value" (`.some`). The service applies only the
/// provided fields, in one mutation, so a multi-field restyle (e.g. the MCP `canvas_connector_edit`
/// tool) is a single undo step. Same optional "leave unchanged" (`nil`) vs "set" (`.some`)
/// semantics as `EditCardFields`.
///
/// Note `strokeColorHex` here is single-Optional with "leave unchanged" semantics — unlike
/// `ConnectorStyle.strokeColorHex`, where `nil` means "unset / adaptive". A partial restyle cannot
/// express "clear the colour back to unset" through this bag (the same as today's `setStyle`); the
/// dedicated `setStrokeColor(colorHex: nil)` path owns clearing.
struct ConnectorStyleChange: Sendable, Equatable {
    var cap: ConnectorEndpointCap?
    var routing: ConnectorRouting?
    var strokeColorHex: String?
    var strokeWidth: Double?

    init(
        cap: ConnectorEndpointCap? = nil,
        routing: ConnectorRouting? = nil,
        strokeColorHex: String? = nil,
        strokeWidth: Double? = nil
    ) {
        self.cap = cap
        self.routing = routing
        self.strokeColorHex = strokeColorHex
        self.strokeWidth = strokeWidth
    }
}
