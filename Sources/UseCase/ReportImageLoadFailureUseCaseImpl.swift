import Foundation

/// Logs that a placed canvas image is permanently unavailable, via the diagnostics capability port.
/// The canvas (the only place that knows a draw fetch ended in a persistent placeholder) drives this
/// through the ViewModel; routing it here keeps the `os` sink sealed in Infrastructure while giving
/// Presentation a Console trail for the otherwise-silent grey box (ticket 37B774CD).
final class ReportImageLoadFailureUseCaseImpl: ReportImageLoadFailureUseCase, Sendable {
    private let diagnostics: any DiagnosticsLoggingProtocol

    init(diagnostics: any DiagnosticsLoggingProtocol) {
        self.diagnostics = diagnostics
    }

    func execute(assetID: UUID, reason: ImageLoadFailureReason) {
        let cause: String
        switch reason {
        case .missingAsset: cause = "sidecar asset file is missing"
        case .undecodableData: cause = "sidecar bytes are not a decodable image"
        case .unreadable: cause = "sidecar could not be read after repeated attempts"
        }
        // assetID is operational (safe to surface); the message carries no user content, no path.
        diagnostics.log("canvas image \(assetID) unavailable: \(cause); showing placeholder",
                        level: .error)
    }
}
