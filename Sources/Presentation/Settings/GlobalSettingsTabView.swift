import SwiftUI

/// The Settings → Global tab: board background / text colour, and the user-managed colour palette.
///
/// The colour palette is the **one** place that leans on the OS colour picker (`ColorPicker`): the
/// app offers a small curated set of recurring colours managed here (add / remove / recolour /
/// relabel / reorder), so other colour-choosing sites can eventually pick from this palette instead
/// of opening the system picker.
struct GlobalSettingsTabView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Background Color") {
                ClearablePaletteColorPicker(
                    selection: $viewModel.backgroundColorHex,
                    defaultColor: .boardDefaultBackground,
                    title: "Color",
                    onEdit: { viewModel.markDirty() }
                )
            }

            Section("Text Color") {
                ClearablePaletteColorPicker(
                    selection: $viewModel.textColorHex,
                    defaultColor: .boardDefaultText,
                    title: "Color",
                    onEdit: { viewModel.markDirty() }
                )
            }

            Section("Color Palette") {
                ForEach(viewModel.colorPalette) { color in
                    PaletteColorRowView(viewModel: viewModel, color: color)
                }
                .onMove { viewModel.movePaletteColor(fromOffsets: $0, toOffset: $1) }
                Button {
                    viewModel.addPaletteColor()
                } label: {
                    Label("Add Color", systemImage: "plus")
                }
                Text("""
                A reusable set of colours. Drag to reorder. The label is optional — name a colour \
                (e.g. "Accent") to recognise it at a glance.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Palette colour row

/// One editable palette colour: a colour well + an optional label field + a delete button. The
/// colour and label setters guard same-value write-backs so a redraw never marks the form dirty.
private struct PaletteColorRowView: View {
    let viewModel: SettingsViewModel
    let color: SettingsViewModel.EditablePaletteColor
    @Environment(\.self) private var environment

    var body: some View {
        HStack(spacing: 10) {
            LazyColorWell(selection: colorBinding, help: "Edit color")
            TextField("Label", text: labelBinding)
                .textFieldStyle(.roundedBorder)
            Button(role: .destructive) {
                viewModel.deletePaletteColor(color.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this color")
        }
        .padding(.vertical, 2)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: color.colorHex) },
            set: { viewModel.setPaletteColor($0.toHex(in: environment), for: color.id) }
        )
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { color.label },
            set: { viewModel.setPaletteLabel($0, for: color.id) }
        )
    }
}
