import SwiftUI

// MARK: - Visual Helpers

extension KanbanBoardView {

    var boardBackgroundColor: Color {
        viewModel.board?.settings.global.backgroundColorHex.map { Color(hex: $0) }
            ?? .boardDefaultBackground
    }

    var boardTextColor: Color {
        // Per-board text colour wins; falls back to the shared global text colour, then the default.
        if let hex = viewModel.board?.settings.board.textColorHex { return Color(hex: hex) }
        return viewModel.board?.settings.global.textColorHex.map { Color(hex: $0) }
            ?? .boardDefaultText
    }

    /// Per-column header background: the column's own colour, else `nil` (no fill).
    func columnHeaderColor(for column: ColumnResponse) -> Color? {
        column.headerColorHex.map { Color(hex: $0) }
    }

    /// Per-column header **text** colour (the column title): the column's own colour, else the
    /// board text colour.
    func columnHeaderTextColor(for column: ColumnResponse) -> Color {
        if let hex = column.headerTextColorHex { return Color(hex: hex) }
        return boardTextColor
    }

    /// Per-column body (card-stack area) background: the column's own colour, else the default tint.
    func columnBodyColor(for column: ColumnResponse) -> Color {
        if let hex = column.bodyColorHex { return Color(hex: hex) }
        return Color.secondary.opacity(0.08)
    }

    func columnEditingField(for column: ColumnResponse) -> some View {
        TextField("Column name", text: $editingTitle, onCommit: {
            commitColumnRename(column.id)
        })
        .textFieldStyle(.plain)
        .font(.headline)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.accentColor, lineWidth: 1)
        )
        .focused($focusedField, equals: .column(column.id))
        .onExitCommand { cancelEditing() }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .column(column.id), newValue != .column(column.id) {
                commitColumnRename(column.id)
            }
        }
        .onAppear { focusedField = .column(column.id) }
    }

    /// Per-column status-indicator dot colour: the column's own `indicatorColorHex`, else a fixed
    /// neutral default. The dot no longer follows the card's status colour (todo/inProgress/done) —
    /// it is now a per-column appearance like the header/body colours.
    func columnIndicatorColor(for column: ColumnResponse) -> Color {
        column.indicatorColorHex.map { Color(hex: $0) } ?? .boardDefaultStatusDot
    }

    func statusDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    /// Card fill: editing / selection tints win, else the per-board card background, else default.
    /// (Card colours are board-wide, not per-column.)
    func cardBackground(for card: CardSummary) -> some ShapeStyle {
        if editingTarget == .card(card.id) { return AnyShapeStyle(Color.accentColor.opacity(0.08)) }
        if viewModel.selectedCardID == card.id { return AnyShapeStyle(card.status.displayColor.opacity(0.12)) }
        let base = viewModel.board?.settings.board.cardBackgroundColorHex.map { Color(hex: $0) }
            ?? .boardDefaultCardBackground
        return AnyShapeStyle(base)
    }

    /// Per-board card **text** colour; `nil` ⇒ the system primary colour.
    var cardTextColor: Color {
        viewModel.board?.settings.board.cardTextColorHex.map { Color(hex: $0) } ?? .primary
    }

    /// Per-column header border overlay: the column's own border colour, else `.clear` (no border).
    @ViewBuilder
    func columnHeaderBorderOverlay(for column: ColumnResponse) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(column.headerBorderColorHex.map { Color(hex: $0) } ?? .clear, lineWidth: 1)
    }

    /// Per-column body border overlay: the column's own border colour, else `.clear` (no border).
    @ViewBuilder
    func columnBodyBorderOverlay(for column: ColumnResponse) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(column.bodyBorderColorHex.map { Color(hex: $0) } ?? .clear, lineWidth: 1)
    }

    /// Card border stroke — colour and width derived **together** so the priority ladder
    /// (editing → selected → user-set board-wide colour → none) lives in exactly one place.
    /// Keeping width and colour in one return value removes the risk of the two drifting out of
    /// lockstep (a colour with zero width, or vice-versa).
    func cardBorder(for card: CardSummary) -> (color: Color, width: CGFloat) {
        if editingTarget == .card(card.id) { return (.accentColor, 2) }
        if viewModel.selectedCardID == card.id { return (card.status.displayColor, 2) }
        if let hex = viewModel.board?.settings.board.cardBorderColorHex { return (Color(hex: hex), 1) }
        return (.clear, 0)
    }

    /// Card border overlay built from the single `cardBorder(for:)` source of truth.
    @ViewBuilder
    func cardBorderOverlay(for card: CardSummary) -> some View {
        let border = cardBorder(for: card)
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(border.color, lineWidth: border.width)
    }

    var addColumnButton: some View {
        Button {
            Task { await viewModel.addColumn(title: "New Column") }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus.rectangle")
                    .font(.title3)
                Text("Add Column")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(minWidth: 120, maxWidth: 120, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
