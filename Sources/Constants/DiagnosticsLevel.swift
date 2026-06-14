import Foundation

/// Severity of a diagnostic message. Shared contract vocabulary between the Domain-facing
/// `DiagnosticsLoggingProtocol` port and the Infrastructure `DiagnosticsSinkProtocol` sink, so it
/// lives in `Constants`: both layers must name the same levels, and Infrastructure — which maps each
/// case to an `os` `OSLogType` — cannot import the Domain/Entities port (it would be an upward
/// import). This is exactly the `Constants` use case: ≥2 layers share it and one of them is
/// Infrastructure.
enum DiagnosticsLevel: Sendable {
    /// Verbose tracing, suppressed in release log views by default.
    case debug
    /// Routine, expected outcomes worth recording (e.g. "GC reclaimed N assets").
    case info
    /// A failure or degraded condition that should surface in `Console.app`.
    case error
}
