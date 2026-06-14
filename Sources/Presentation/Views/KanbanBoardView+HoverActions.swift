import SwiftUI

extension KanbanBoardView {
    func columnHoverActions(for column: ColumnResponse) -> some View {
        HStack(spacing: 6) {
            Button {
                editingTitle = column.title
                editingTarget = .column(column.id)
            } label: {
                Image(systemName: "pencil")
            }
            .help("Rename Column")

            Button {
                columnIDToDelete = column.id
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .help("Delete Column")
        }
        .font(.caption)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    func cardHoverActions(for card: CardSummary) -> some View {
        HStack(spacing: 2) {
            Button {
                // Only show the checkmark when the write actually landed — never lie about success.
                // A failed write is non-fatal but routed to diagnostics so it is not a silent no-op.
                guard copyToPasteboard(card.id.uuidString) else {
                    viewModel.reportPasteboardWriteFailure(label: "card ID")
                    return
                }
                copiedCardID = card.id
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    if copiedCardID == card.id { copiedCardID = nil }
                }
            } label: {
                Image(systemName: copiedCardID == card.id ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copiedCardID == card.id ? Color.green : Color.secondary)
                    .frame(width: 22, height: 22)
            }
            .help("Copy Card ID")

            Button {
                editingTitle = card.title
                editingTarget = .card(card.id)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 22, height: 22)
            }
            .help("Rename Card")

            Button {
                cardIDToDelete = card.id
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(width: 22, height: 22)
            }
            .help("Delete Card")
        }
        .font(.caption2)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(4)
    }
}
