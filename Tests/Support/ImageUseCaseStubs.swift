import Foundation
@testable import KanvasCore

/// Shared no-op stub for the fire-and-forget image-load-failure diagnostic. Kept in `Tests/Support`
/// (not re-declared per file) so the next canvas-image use case doesn't force the same edit across
/// every `BoardViewModel` test fixture. Stateless, so plain `Sendable` (no `@unchecked`).
final class StubReportImageLoadFailure: ReportImageLoadFailureUseCase, Sendable {
    func execute(assetID: UUID, reason: ImageLoadFailureReason) {}
}

/// Shared no-op stub for the fire-and-forget pasteboard-write-failure diagnostic (ticket 8E857E6F).
/// Stateless, so plain `Sendable` (no `@unchecked`).
final class StubReportPasteboardWriteFailure: ReportPasteboardWriteFailureUseCase, Sendable {
    func execute(label: String) {}
}
