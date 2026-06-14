import SwiftUI

/// Floating panel for the app-wide sticky-label registry. Lists every label (name + colour,
/// both editable), lets you add a new one, and assigns/unassigns labels to the sticky the
/// panel was opened from — double-click a row (or click its checkmark) to toggle assignment.
struct LabelManagerView: View {
    @Bindable var viewModel: BoardViewModel

    /// Seed colour for a freshly created label.
    private static let newLabelColor = "FF9500"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if viewModel.labels.isEmpty {
                Text("No labels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(viewModel.labels) { label in
                            LabelManagerRow(
                                label: label,
                                isAssigned: isAssigned(label),
                                onRename: { newName in rename(label, to: newName) },
                                onRecolor: { hex in recolor(label, to: hex) },
                                onToggle: { toggle(label) },
                                onDelete: { Task { await viewModel.deleteLabel(id: label.id) } }
                            )
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            Divider()

            Button {
                Task { await viewModel.addLabel(name: "New label", colorHex: Self.newLabelColor) }
            } label: {
                Label("New Label", systemImage: "plus")
                    .font(.callout)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 260)
        .background(.bar, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
        .padding(10)
    }

    private var header: some View {
        HStack {
            Text("Labels").font(.headline)
            Spacer()
            Button {
                viewModel.closeLabelManager()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private func isAssigned(_ label: StickyLabelResponse) -> Bool {
        viewModel.labelManagerSticky?.labels.contains { $0.id == label.id } ?? false
    }

    private func rename(_ label: StickyLabelResponse, to name: String) {
        Task { await viewModel.editLabel(id: label.id, name: name, colorHex: label.colorHex) }
    }

    private func recolor(_ label: StickyLabelResponse, to hex: String) {
        Task { await viewModel.editLabel(id: label.id, name: label.name, colorHex: hex) }
    }

    private func toggle(_ label: StickyLabelResponse) {
        guard let stickyID = viewModel.labelManagerStickyID else { return }
        Task { await viewModel.toggleStickyLabel(stickyID: stickyID, labelID: label.id) }
    }
}

/// One label row: a colour menu, an inline-editable name, an assignment toggle, and delete.
private struct LabelManagerRow: View {
    let label: StickyLabelResponse
    let isAssigned: Bool
    let onRename: (String) -> Void
    let onRecolor: (String) -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var name: String = ""
    @FocusState private var nameFocused: Bool
    /// Coalesces rapid-fire swatch taps or custom-picker drags into one persisted edit,
    /// so fast interactions don't flood the (5-deep) undo history.
    @State private var recolorTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            PaletteColorPicker(selection: colorHexBinding)
                .help("Color")
            TextField("Label name", text: $name)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .onSubmit { commitName() }
            Spacer(minLength: 4)
            Button(action: onToggle) {
                Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isAssigned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isAssigned ? "Remove from sticky" : "Add to sticky")
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete label")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isAssigned ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        // Double-click a row to assign / unassign (the spec's gesture). The name field consumes
        // its own clicks, so a double-click there edits text rather than toggling.
        .onTapGesture(count: 2) { onToggle() }
        // Seed the editable name from the model, re-seeding if the label id changes (list reuse).
        .task(id: label.id) { name = label.name }
        .onChange(of: nameFocused) { _, focused in
            if !focused { commitName() }
        }
        // Drop a still-pending debounced recolor if the row goes away (panel closed / row reused).
        .onDisappear { recolorTask?.cancel() }
    }

    /// Reads the stored hex directly; on change, schedules a 300 ms-debounced recolor so both
    /// swatch taps and custom-picker drags coalesce into one persisted edit per gesture.
    private var colorHexBinding: Binding<String> {
        Binding(
            get: { label.colorHex },
            set: { hex in
                guard hex != label.colorHex else { return }
                recolorTask?.cancel()
                recolorTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    onRecolor(hex)
                }
            }
        )
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != label.name else {
            name = label.name  // reject blank / revert to the stored name
            return
        }
        onRename(trimmed)
    }
}
