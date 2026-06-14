import Foundation

struct SetConnectorCapRequest: ValidatableRequest {
    let connectorID: UUID
    /// `ConnectorEndpointCap` raw value ("line" / "arrow") — validated here since Presentation
    /// never imports the domain enum.
    let cap: String

    func validate() throws {
        guard ConnectorEndpointCap(rawValue: cap) != nil else { throw ValidationError.invalidConnectorCap }
    }
}
