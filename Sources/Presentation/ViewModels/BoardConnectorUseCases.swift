import Foundation

/// The canvas-connector use cases, bundled so `BoardViewModel` injects one dependency instead of
/// several — keeping its initializer and body within the length budgets. Consumed by the
/// `BoardViewModel+ConnectorActions` extension.
struct BoardConnectorUseCases: Sendable {
    let add: AddConnectorUseCase
    let delete: DeleteConnectorUseCase
    let setCap: SetConnectorCapUseCase
    let setRouting: SetConnectorRoutingUseCase
    let setStrokeColor: SetConnectorStrokeColorUseCase
    let setStrokeWidth: SetConnectorStrokeWidthUseCase
    let reconnect: ReconnectConnectorUseCase
    let setWaypoint: SetConnectorWaypointUseCase
}
