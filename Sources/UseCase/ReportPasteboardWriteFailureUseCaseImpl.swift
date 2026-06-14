import Foundation

/// Logs that a copy-to-pasteboard write failed, via the diagnostics capability port. The board's
/// copy buttons (the only place that knows `NSPasteboard.setString` returned `false`) drive this
/// through the ViewModel; routing it here keeps the `os` sink sealed in Infrastructure while giving
/// Presentation a Console trail for the otherwise-silent no-op (ticket 8E857E6F). The App shell's
/// injected pasteboard closure already propagates the `Bool` up to Presentation; this use case is the
/// missing "observe the failure" half of that path.
final class ReportPasteboardWriteFailureUseCaseImpl: ReportPasteboardWriteFailureUseCase, Sendable {
    private let diagnostics: any DiagnosticsLoggingProtocol

    init(diagnostics: any DiagnosticsLoggingProtocol) {
        self.diagnostics = diagnostics
    }

    func execute(label: String) {
        // `label` is a fixed operational description of what was being copied (no user content); safe
        // to surface. A failed clipboard write is non-fatal (the user simply has nothing on the
        // pasteboard) but it is a degraded outcome that should reach Console, so it logs at `.error`.
        diagnostics.log("pasteboard write failed for \(label); clipboard left unchanged", level: .error)
    }
}
