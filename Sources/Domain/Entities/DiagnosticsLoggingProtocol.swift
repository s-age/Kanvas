import Foundation

/// Cross-layer capability port for emitting diagnostic logs from layers that may not import `os`
/// (UseCase / Domain). Declared in `Domain/Entities` — the shared leaf — so both UseCase and
/// Repository can reference it without an upward import, the same placement `DBProtocol` uses.
/// Capability ports are the sanctioned exception to Domain/Entities' "value types only" guidance.
///
/// The concrete sink lives in Infrastructure (`OSDiagnosticsLogger`, behind `DiagnosticsSinkProtocol`);
/// the Repository adapter `DiagnosticsLogger` bridges this port to it, so the `os` dependency never
/// leaks above Infrastructure. Wiring order: `RepositoryContainer` builds the adapter from the infra
/// sink and exposes it as `diagnostics`; the consuming layer injects that existential.
protocol DiagnosticsLoggingProtocol: Sendable {
    /// Emits one diagnostic at the given severity. `message` is the public summary (counts, asset
    /// UUIDs — safe to surface); `privateDetail`, when non-nil, is logged with redacting privacy so
    /// dynamic values that may embed a filesystem path or user content (e.g. an `Error`'s text) are
    /// not forced public. Best-effort and non-throwing: a logging failure must never alter the
    /// caller's control flow.
    func log(_ message: String, privateDetail: String?, level: DiagnosticsLevel)
}

extension DiagnosticsLoggingProtocol {
    /// Convenience for a message carrying no sensitive detail.
    func log(_ message: String, level: DiagnosticsLevel) {
        log(message, privateDetail: nil, level: level)
    }
}
