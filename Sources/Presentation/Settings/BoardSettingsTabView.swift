import SwiftUI

struct BoardSettingsTabView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Card Order") {
                Picker("Sort Policy", selection: sortPolicyBinding) {
                    ForEach(CardSortPolicyResponse.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                Picker("New Card Position", selection: newCardPositionBinding) {
                    ForEach(NewCardPositionResponse.allCases, id: \.self) { position in
                        Text(position.displayName).tag(position)
                    }
                }
            }

            Section("Card Colors") {
                ClearablePaletteColorPicker(
                    selection: $viewModel.cardBackgroundColorHex,
                    defaultColor: .boardDefaultCardBackground,
                    title: "Background",
                    onEdit: { viewModel.markDirty() }
                )
                ClearablePaletteColorPicker(
                    selection: $viewModel.cardTextColorHex,
                    defaultColor: .boardDefaultText,
                    title: "Text",
                    onEdit: { viewModel.markDirty() }
                )
                ClearablePaletteColorPicker(
                    selection: $viewModel.cardBorderColorHex,
                    defaultColor: .clear,
                    title: "Border",
                    onEdit: { viewModel.markDirty() }
                )
            }

            columnsSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Columns editor

private extension BoardSettingsTabView {

    @ViewBuilder
    var columnsSection: some View {
        ForEach(viewModel.editableColumns) { column in
            Section {
                columnRow(column)
            } header: {
                Text(column.title.isEmpty ? "Untitled" : column.title)
            }
        }

        if viewModel.isTemplateScope {
            Section {
                Button {
                    viewModel.addColumn()
                } label: {
                    Label("Add Column", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    func columnRow(_ column: SettingsViewModel.EditableColumn) -> some View {
        if viewModel.isTemplateScope {
            TextField("Title", text: titleBinding(column.id))
        }
        // The completion ("Done") column can be re-designated from here in either scope — useful
        // when columns have been reordered and the wrong one is flagged.
        Toggle("Done column (auto-complete target)", isOn: completionBinding(column.id))
        if viewModel.isTemplateScope {
            reorderDeleteControls(column.id)
        }
        ClearablePaletteColorPicker(
            selection: headerColorBinding(column.id),
            defaultColor: .boardDefaultBackground,
            title: "Header Background",
            onEdit: { viewModel.markDirty() }
        )
        ClearablePaletteColorPicker(
            selection: headerTextColorBinding(column.id),
            defaultColor: .boardDefaultText,
            title: "Header Text",
            onEdit: { viewModel.markDirty() }
        )
        ClearablePaletteColorPicker(
            selection: headerBorderColorBinding(column.id),
            defaultColor: .clear,
            title: "Header Border",
            onEdit: { viewModel.markDirty() }
        )
        ClearablePaletteColorPicker(
            selection: bodyColorBinding(column.id),
            defaultColor: .boardDefaultBackground,
            title: "Body Background",
            onEdit: { viewModel.markDirty() }
        )
        ClearablePaletteColorPicker(
            selection: bodyBorderColorBinding(column.id),
            defaultColor: .clear,
            title: "Body Border",
            onEdit: { viewModel.markDirty() }
        )
        ClearablePaletteColorPicker(
            selection: indicatorColorBinding(column.id),
            defaultColor: .boardDefaultStatusDot,
            title: "Indicator",
            onEdit: { viewModel.markDirty() }
        )
    }

    @ViewBuilder
    func reorderDeleteControls(_ id: UUID) -> some View {
        HStack {
            Button {
                viewModel.moveColumnUp(id)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(!viewModel.canMoveColumnUp(id))

            Button {
                viewModel.moveColumnDown(id)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(!viewModel.canMoveColumnDown(id))

            Spacer()

            Button(role: .destructive) {
                viewModel.deleteColumn(id)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(viewModel.editableColumns.count <= 1)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Bindings

private extension BoardSettingsTabView {

    func headerColorBinding(_ id: UUID) -> Binding<String?> {
        Binding(
            get: { viewModel.editableColumns.first { $0.id == id }?.headerColorHex },
            set: { viewModel.setHeaderColor($0, for: id) }
        )
    }

    func headerTextColorBinding(_ id: UUID) -> Binding<String?> {
        Binding(
            get: { viewModel.editableColumns.first { $0.id == id }?.headerTextColorHex },
            set: { viewModel.setHeaderTextColor($0, for: id) }
        )
    }

    func bodyColorBinding(_ id: UUID) -> Binding<String?> {
        Binding(
            get: { viewModel.editableColumns.first { $0.id == id }?.bodyColorHex },
            set: { viewModel.setBodyColor($0, for: id) }
        )
    }

    func headerBorderColorBinding(_ id: UUID) -> Binding<String?> {
        Binding(
            get: { viewModel.editableColumns.first { $0.id == id }?.headerBorderColorHex },
            set: { viewModel.setHeaderBorderColor($0, for: id) }
        )
    }

    func bodyBorderColorBinding(_ id: UUID) -> Binding<String?> {
        Binding(
            get: { viewModel.editableColumns.first { $0.id == id }?.bodyBorderColorHex },
            set: { viewModel.setBodyBorderColor($0, for: id) }
        )
    }

    func indicatorColorBinding(_ id: UUID) -> Binding<String?> {
        Binding(
            get: { viewModel.editableColumns.first { $0.id == id }?.indicatorColorHex },
            set: { viewModel.setIndicatorColor($0, for: id) }
        )
    }

    func completionBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.editableColumns.first { $0.id == id }?.isCompletionColumn ?? false },
            set: { viewModel.setColumnCompletion(id, isOn: $0) }
        )
    }

    func titleBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.editableColumns.first { $0.id == id }?.title ?? "" },
            set: { viewModel.setColumnTitle($0, for: id) }
        )
    }

    // A Picker writes its current value back on re-render, not only on user change — guard the
    // same-value write-back so a redraw never marks the form dirty (arch-presentation pattern).
    var sortPolicyBinding: Binding<CardSortPolicyResponse> {
        Binding(
            get: { viewModel.cardSortPolicy },
            set: { newValue in
                guard newValue != viewModel.cardSortPolicy else { return }
                viewModel.cardSortPolicy = newValue
                viewModel.markDirty()
            }
        )
    }

    var newCardPositionBinding: Binding<NewCardPositionResponse> {
        Binding(
            get: { viewModel.newCardPosition },
            set: { newValue in
                guard newValue != viewModel.newCardPosition else { return }
                viewModel.newCardPosition = newValue
                viewModel.markDirty()
            }
        )
    }
}
