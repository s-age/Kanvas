import SwiftUI
import UniformTypeIdentifiers

// MARK: - Column drag type

struct ColumnDragItem: Codable, Transferable {
    let columnID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

// MARK: - Card drop target

enum CardDropTarget: Equatable {
    case before(cardID: UUID)
    case endOf(columnID: UUID)
}

// MARK: - Drag & Drop

extension KanbanBoardView {

    // MARK: Card hints

    var insertionIndicator: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 3)
            .padding(.horizontal, 8)
            .transition(.opacity)
    }

    func updateDropHint(card: CardSummary, isTargeted: Bool) {
        if isTargeted {
            cardDropTarget = .before(cardID: card.id)
        } else if cardDropTarget == .before(cardID: card.id) {
            cardDropTarget = nil
        }
    }

    func dropCard(_ droppedIDs: [String], before target: CardSummary, in column: ColumnResponse) -> Bool {
        guard let raw = droppedIDs.first, let draggedID = UUID(uuidString: raw) else { return false }
        guard draggedID != target.id else { return false }
        Task {
            await viewModel.moveCard(id: draggedID, toColumn: column.id, before: target.id)
        }
        return true
    }

    @discardableResult
    func dropCardAtEnd(_ droppedIDs: [String], in column: ColumnResponse) -> Bool {
        cardDropTarget = nil
        guard let raw = droppedIDs.first,
              let cardID = UUID(uuidString: raw) else { return false }
        Task { await viewModel.moveCard(id: cardID, toColumn: column.id, before: nil) }
        return true
    }

    // MARK: Card end drop zone

    func cardEndDropZone(for column: ColumnResponse) -> some View {
        Color.clear
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                if cardDropTarget == .endOf(columnID: column.id) {
                    insertionIndicator
                        .padding(.top, 4)
                }
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                dropCardAtEnd(items, in: column)
            } isTargeted: { isTargeted in
                if isTargeted {
                    cardDropTarget = .endOf(columnID: column.id)
                } else if cardDropTarget == .endOf(columnID: column.id) {
                    cardDropTarget = nil
                }
            }
            .animation(.easeInOut(duration: 0.15), value: cardDropTarget == .endOf(columnID: column.id))
    }

    // MARK: Column reorder gap

    /// A narrow gap between columns that serves as the drop zone for column
    /// reorder. `column` is the column to the right of this gap, or `nil`
    /// for the trailing gap after the last column.
    func columnDropGap(before column: ColumnResponse?) -> some View {
        let gapIndex = column?.sortIndex ?? (viewModel.board?.columns.count ?? 0)
        let isActive = dropTargetColumnGapIndex == gapIndex
        return Color.clear
            .frame(width: 16)
            .frame(maxHeight: .infinity)
            .overlay {
                if isActive {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .dropDestination(for: ColumnDragItem.self) { items, _ in
                dropTargetColumnGapIndex = nil
                guard let item = items.first else { return false }
                guard item.columnID != column?.id else { return false }
                Task {
                    await viewModel.reorderColumn(id: item.columnID, before: column?.id)
                }
                return true
            } isTargeted: { isTargeted in
                if isTargeted {
                    dropTargetColumnGapIndex = gapIndex
                } else if dropTargetColumnGapIndex == gapIndex {
                    dropTargetColumnGapIndex = nil
                }
            }
    }
}
