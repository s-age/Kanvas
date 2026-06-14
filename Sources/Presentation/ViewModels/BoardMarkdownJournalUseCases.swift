import Foundation

/// The durable Markdown autosave journal use cases (record / list / clear), bundled so
/// `BoardViewModel` injects one dependency instead of three (ticket 44C9D3C2). They back the
/// `MarkdownAutosaveQueue`'s write-ahead journaling and the startup restore, consumed by the
/// `BoardViewModel+CardActions` extension.
struct BoardMarkdownJournalUseCases: Sendable {
    let record: RecordMarkdownJournalUseCase
    let list: any ListMarkdownJournalUseCase
    let clear: ClearMarkdownJournalUseCase
}
