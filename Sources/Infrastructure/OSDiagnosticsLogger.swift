import Foundation
import os

/// `os.Logger`-backed diagnostics sink. The single sanctioned place (alongside `FileLock`) that
/// emits to the unified system log; it maps each `DiagnosticsLevel` to the matching `Logger` method
/// so messages show up in `Console.app` under the configured subsystem/category. Lives in
/// Infrastructure because only this layer may import `os`.
///
/// The public `message` carries operational signals (counts, asset UUIDs) safe to surface, so it is
/// logged `.public`; `privateDetail` keeps `os.Logger`'s default redaction so a dynamic value that
/// may embed a filesystem path or user content (an interpolated `Error`) is not forced public.
final class OSDiagnosticsLogger: DiagnosticsSinkProtocol, Sendable {
    private let logger: Logger

    init(subsystem: String = "com.kanvas.app", category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func emit(_ message: String, privateDetail: String?, level: DiagnosticsLevel) {
        guard let privateDetail else {
            switch level {
            case .debug: logger.debug("\(message, privacy: .public)")
            case .info: logger.info("\(message, privacy: .public)")
            case .error: logger.error("\(message, privacy: .public)")
            }
            return
        }
        switch level {
        case .debug: logger.debug("\(message, privacy: .public): \(privateDetail, privacy: .private)")
        case .info: logger.info("\(message, privacy: .public): \(privateDetail, privacy: .private)")
        case .error: logger.error("\(message, privacy: .public): \(privateDetail, privacy: .private)")
        }
    }
}
