import Foundation
@testable import KanvasCore

/// Records every diagnostic the system under test emits so a test can assert observability
/// (orphan-asset GC count, per-file failure, reachability abort). Mock at the port boundary —
/// `DiagnosticsLoggingProtocol` — never the `os.Logger` sink.
///
/// `@unchecked Sendable` is safe here: mutation happens only on a test's serial flow.
final class SpyDiagnosticsLogger: DiagnosticsLoggingProtocol, @unchecked Sendable {
    private(set) var messages: [(message: String, privateDetail: String?, level: DiagnosticsLevel)] = []

    func log(_ message: String, privateDetail: String?, level: DiagnosticsLevel) {
        messages.append((message, privateDetail, level))
    }

    /// Convenience for assertions: every public message at the given level.
    func messages(at level: DiagnosticsLevel) -> [String] {
        messages.filter { $0.level == level }.map(\.message)
    }

    /// Convenience for assertions: the redacted `privateDetail` payloads at the given level.
    func privateDetails(at level: DiagnosticsLevel) -> [String] {
        messages.filter { $0.level == level }.compactMap(\.privateDetail)
    }
}
