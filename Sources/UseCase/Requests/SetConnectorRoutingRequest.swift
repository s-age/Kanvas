import Foundation

struct SetConnectorRoutingRequest: ValidatableRequest {
    let connectorID: UUID
    /// `ConnectorRouting` raw value ("straight" / "elbow" / "curve") — validated here since
    /// Presentation never imports the domain enum.
    let routing: String

    func validate() throws {
        guard ConnectorRouting(rawValue: routing) != nil else { throw ValidationError.invalidConnectorRouting }
    }
}
