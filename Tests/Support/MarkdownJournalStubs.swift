import Foundation
@testable import KanvasCore

// No-op stubs for the durable Markdown journal use cases, so `BoardViewModel` test factories can
// supply a `BoardMarkdownJournalUseCases` bundle without exercising the journal (ticket 44C9D3C2).
// Shared (not `private`) so every `makeBoardViewModel` factory reuses them.

struct StubRecordMarkdownJournal: AsyncUseCase, Sendable {
    func execute(_ request: RecordMarkdownJournalRequest) async throws {}
}

struct StubClearMarkdownJournal: AsyncUseCase, Sendable {
    func execute(_ request: ClearMarkdownJournalRequest) async throws {}
}

struct StubListMarkdownJournal: ListMarkdownJournalUseCase, Sendable {
    func execute() async throws -> [PendingMarkdownEditResponse] { [] }
}

/// The no-op bundle every `BoardViewModel` test factory can drop in.
func stubMarkdownJournalUseCases() -> BoardMarkdownJournalUseCases {
    BoardMarkdownJournalUseCases(
        record: StubRecordMarkdownJournal(),
        list: StubListMarkdownJournal(),
        clear: StubClearMarkdownJournal()
    )
}
