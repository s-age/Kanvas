import SwiftUI

struct KanbanBoardView: View {
    @Bindable var viewModel: BoardViewModel
    // Injected from App/ so Presentation never imports AppKit (presentation_no_appkit rule).
    // Returns whether the pasteboard write succeeded.
    let copyToPasteboard: @MainActor (String) -> Bool
    // Editing state is `internal` (not `private`) so the editing-lifecycle helpers in
    // KanbanBoardView+Editing.swift can drive it from the sibling file.
    @State var editingTarget: EditingField?
    @State var editingTitle = ""
    @State var cardDropTarget: CardDropTarget?
    @State private var hoveredCardID: UUID?
    @State private var hoveredColumnID: UUID?
    @State var dropTargetColumnGapIndex: Int?
    @State var cardIDToDelete: UUID?
    @State var columnIDToDelete: UUID?
    // Tracks which card's copy button is showing the checkmark feedback; cleared after ~1 s.
    @State var copiedCardID: UUID?
    @FocusState var focusedField: EditingField?
    // Board rename prompt state. Internal (not private) so the `boardPicker` helper in the sibling
    // file `KanbanBoardView+BoardPicker.swift` can drive it. `boardRenameText` seeds the alert.
    @State var isRenamingBoard = false
    @State var boardRenameText = ""
    @Environment(\.openWindow) private var openWindow

    enum EditingField: Hashable {
        case card(UUID)
        case column(UUID)
    }

    var body: some View {
        // The alert + confirmation-dialog stack lives in `KanbanBoardView+Modals.swift` to keep this
        // file within the file/type length budgets.
        boardModals(boardContent)
    }

    private var boardContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(viewModel.board?.columns ?? []) { column in
                    columnDropGap(before: column)
                    columnView(for: column)
                }
                columnDropGap(before: nil)
                addColumnButton
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            // Clicking any empty area outside the rename field commits it. macOS does not
            // resign a TextField on a background click, so `onChange(of: focusedField)`
            // never fires there — this catches it explicitly. Cards/buttons/the field
            // itself are interactive children and consume their own taps first.
            .contentShape(Rectangle())
            .onTapGesture { commitActiveEdit() }
        }
        .frame(maxHeight: .infinity)
        .background(boardBackgroundColor)
        .foregroundStyle(boardTextColor)
        .navigationTitle(viewModel.activeBoardTitle)
        .task {
            await viewModel.load()
            // Once-per-launch maintenance that writes (orphan-asset GC, Markdown-journal restore) —
            // kept out of `load()` so the store-watcher refresh stays read-only (ticket 7935A21E).
            await viewModel.performStartupMaintenance()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                boardPicker
            }
            ToolbarItem(placement: .principal) {
                cardSearchField
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: WindowID.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Board Settings")
            }
        }
    }

    // MARK: - Search filter

    /// The cards of `column` to render under the active search filter. With no filter (`searchText`
    /// blank ⇒ `matchedCardIDs == nil`) every card shows; otherwise only matched cards. The column
    /// itself always renders (even at zero cards), and the header count reads this filtered list.
    private func visibleCards(in column: ColumnResponse) -> [CardSummary] {
        column.cards.filter { viewModel.isCardVisible($0.id) }
    }

    // MARK: - Column

    private func columnView(for column: ColumnResponse) -> some View {
        // Compute the filtered list once per render and pass it to both consumers (the card ForEach
        // and the header count); calling `visibleCards(in:)` twice per column per render was wasteful
        // (PR #123 r1-3).
        let visible = visibleCards(in: column)
        return VStack(alignment: .leading, spacing: 8) {
            columnHeader(for: column, visibleCount: visible.count)
                .foregroundStyle(columnHeaderTextColor(for: column))

            // The header stays pinned; only the cards scroll vertically so a long
            // column no longer clips its lower cards.
            ScrollView(.vertical, showsIndicators: false) {
                // LazyVStack so only the visible cards build their views — important
                // for long, card-heavy columns.
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(visible) { card in
                        cardRow(for: card, in: column)
                    }
                    cardEndDropZone(for: column)
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .dropDestination(for: String.self) { items, _ in
                dropCardAtEnd(items, in: column)
            } isTargeted: { isTargeted in
                if isTargeted {
                    cardDropTarget = .endOf(columnID: column.id)
                } else if cardDropTarget == .endOf(columnID: column.id) {
                    cardDropTarget = nil
                }
            }
        }
        .frame(minWidth: 260, maxWidth: 260, maxHeight: .infinity, alignment: .top)
        .padding(12)
        .background(columnBodyColor(for: column))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(columnBodyBorderOverlay(for: column))
        .contextMenu {
            Button("Rename Column") {
                editingTitle = column.title
                editingTarget = .column(column.id)
            }
            Divider()
            Button("Delete Column", role: .destructive) {
                columnIDToDelete = column.id
            }
        }
    }

    private func columnHeader(for column: ColumnResponse, visibleCount: Int) -> some View {
        HStack {
            if editingTarget == .column(column.id) {
                columnEditingField(for: column)
            } else {
                Text(column.title)
                    .font(.headline)
                if column.isCompletionColumn {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .help("Done column — cards moved here are marked completed")
                }
            }

            Text("\(visibleCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())

            Spacer()

            if hoveredColumnID == column.id && editingTarget != .column(column.id) {
                columnHoverActions(for: column)
                    .transition(.opacity)
            }

            Button {
                Task { await beginEditingNewCard(in: column.id) }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(columnHeaderColor(for: column) ?? .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(columnHeaderBorderOverlay(for: column))
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredColumnID = isHovered ? column.id : nil
            }
        }
        .draggable(ColumnDragItem(columnID: column.id))
    }

}

// MARK: - Card Row

private extension KanbanBoardView {
    func cardRow(for card: CardSummary, in column: ColumnResponse) -> some View {
        VStack(spacing: 0) {
            if editingTarget == .card(card.id) {
                cardEditingRow(for: card, in: column)
            } else {
                cardDisplayRow(for: card, in: column)
            }
        }
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredCardID = isHovered ? card.id : nil
            }
        }
        .onDisappear {
            if hoveredCardID == card.id {
                hoveredCardID = nil
            }
        }
    }

    func cardDisplayRow(for card: CardSummary, in column: ColumnResponse) -> some View {
        VStack(spacing: 4) {
            if cardDropTarget == .before(cardID: card.id) {
                insertionIndicator
            }
            Button {
                commitActiveEdit()
                viewModel.selectCard(id: card.id)
            } label: {
                cardLabel(for: card, in: column)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if hoveredCardID == card.id {
                    cardHoverActions(for: card)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: cardDropTarget == .before(cardID: card.id))
        .draggable(card.id.uuidString)
        .dropDestination(for: String.self) { droppedIDs, _ in
            cardDropTarget = nil
            return dropCard(droppedIDs, before: card, in: column)
        } isTargeted: { isTargeted in
            updateDropHint(card: card, isTargeted: isTargeted)
        }
        .contextMenu {
            Button("Rename Card") {
                editingTitle = card.title
                editingTarget = .card(card.id)
            }
            Divider()
            Button("Delete Card", role: .destructive) {
                cardIDToDelete = card.id
            }
        }
    }

    func cardLabel(for card: CardSummary, in column: ColumnResponse) -> some View {
        HStack(spacing: 8) {
            statusDot(color: columnIndicatorColor(for: column))
            Text(card.title)
                .foregroundStyle(cardTextColor)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(for: card))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(cardBorderOverlay(for: card))
    }

    func cardEditingRow(for card: CardSummary, in column: ColumnResponse) -> some View {
        HStack(spacing: 8) {
            statusDot(color: columnIndicatorColor(for: column))
            TextField("Card title", text: $editingTitle, onCommit: {
                commitCardRename(card.id)
            })
            .textFieldStyle(.plain)
            .focused($focusedField, equals: .card(card.id))
            .onExitCommand { cancelEditing() }
            .onChange(of: focusedField) { oldValue, newValue in
                // Losing focus to any other operation (+, selecting a card, …) commits the rename.
                if oldValue == .card(card.id), newValue != .card(card.id) {
                    commitCardRename(card.id)
                }
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 2)
        )
        .onAppear {
            focusedField = .card(card.id)
        }
    }

}

