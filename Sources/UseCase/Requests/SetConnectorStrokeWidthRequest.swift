import Foundation

struct SetConnectorStrokeWidthRequest: ValidatableRequest {
    let connectorID: UUID
    let width: Double

    func validate() throws {
        try NumericBoundsValidation.validate(
            strokeWidth: width, in: ConnectorStyle.minStrokeWidth...ConnectorStyle.maxStrokeWidth
        )
    }
}
