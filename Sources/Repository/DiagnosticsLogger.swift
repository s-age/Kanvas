import Foundation

/// Repository adapter bridging the Domain `DiagnosticsLoggingProtocol` capability port to the
/// Infrastructure `DiagnosticsSinkProtocol` `os.Logger` sink. Repository is the only layer that may
/// import both `Domain/Entities` (the port) and `Infrastructure/Protocols` (the sink), so the bridge
/// lives here — mirroring how a database gateway would bridge `DBProtocol` to its store. A thin
/// pass-through: it adds no logic, it only lets the upper layers depend on the port while the `os`
/// dependency stays sealed inside Infrastructure.
final class DiagnosticsLogger: DiagnosticsLoggingProtocol, Sendable {
    private let sink: any DiagnosticsSinkProtocol

    init(sink: any DiagnosticsSinkProtocol) {
        self.sink = sink
    }

    func log(_ message: String, privateDetail: String?, level: DiagnosticsLevel) {
        sink.emit(message, privateDetail: privateDetail, level: level)
    }
}
