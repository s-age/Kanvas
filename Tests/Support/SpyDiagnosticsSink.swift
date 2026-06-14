import Foundation
@testable import KanvasCore

/// Records every diagnostic emitted at the Infrastructure **sink** boundary
/// (`DiagnosticsSinkProtocol`) so a store/watcher test can assert it surfaced a silent degradation
/// (a decode failure's file+detail, a watcher setup failure) instead of dropping it. The companion
/// `SpyDiagnosticsLogger` mocks the upper `DiagnosticsLoggingProtocol` port; this mocks the sink the
/// Infrastructure types write to directly.
///
/// `@unchecked Sendable` is safe here: mutation happens only on a test's serial flow.
final class SpyDiagnosticsSink: DiagnosticsSinkProtocol, @unchecked Sendable {
    private(set) var messages: [(message: String, privateDetail: String?, level: DiagnosticsLevel)] = []

    func emit(_ message: String, privateDetail: String?, level: DiagnosticsLevel) {
        messages.append((message, privateDetail, level))
    }

    /// Convenience for assertions: every public message at the given level.
    func messages(at level: DiagnosticsLevel) -> [String] {
        messages.filter { $0.level == level }.map(\.message)
    }
}
