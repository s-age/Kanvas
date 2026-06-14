import Foundation

/// DTO ⇄ entity mapping for the durable Markdown autosave journal. Both the write path
/// (`MarkdownJournalRepository.record`) and the read path (`listAll`) route through here so the
/// encode/decode pair cannot drift.
enum MarkdownJournalMapper {

    static func toEntity(_ dto: MarkdownJournalEntryDTO) -> PendingMarkdownEdit {
        PendingMarkdownEdit(cardID: dto.cardID, content: dto.content, enqueuedAt: dto.enqueuedAt)
    }

    static func toDTO(_ edit: PendingMarkdownEdit) -> MarkdownJournalEntryDTO {
        MarkdownJournalEntryDTO(cardID: edit.cardID, content: edit.content, enqueuedAt: edit.enqueuedAt)
    }
}
