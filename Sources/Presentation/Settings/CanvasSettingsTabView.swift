import SwiftUI

struct CanvasSettingsTabView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Sticky Presets") {
                ForEach(viewModel.stickyPresets) { preset in
                    StickyPresetRowView(viewModel: viewModel, preset: preset)
                }
                Button {
                    viewModel.addPreset()
                } label: {
                    Label("Add Preset", systemImage: "plus")
                }
                Text("""
                Drag a preset from the canvas palette to create a sticky of that size and colour. \
                The label (max 3 chars) shows on the palette swatch.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default Text") {
                Stepper(value: numericBinding(\.defaultStickyFontSize),
                        in: StickyAppearance.minFontSize...StickyAppearance.maxFontSize, step: 1) {
                    Text("Font Size: \(Int(viewModel.defaultStickyFontSize)) pt")
                }
                PaletteColorPicker(selection: defaultTextColorHexBinding, title: "Text Color")
            }

            Section("Sticky Background Colors") {
                ClearablePaletteColorPicker(
                    selection: $viewModel.freeStickyColorHex,
                    defaultColor: Color(hex: StickyAppearance.freeStickyDefaultHex),
                    title: "Free Sticky",
                    onEdit: { viewModel.markDirty() }
                )
                ClearablePaletteColorPicker(
                    selection: $viewModel.taskStickyColorHex,
                    defaultColor: Color(hex: StickyAppearance.taskStickyDefaultHex),
                    title: "Task Sticky",
                    onEdit: { viewModel.markDirty() }
                )
            }

            Section("Initial Zoom") {
                Slider(value: numericBinding(\.initialZoomScale),
                       in: StickyAppearance.minZoom...StickyAppearance.maxZoom) {
                    Text("Zoom")
                } minimumValueLabel: {
                    Text("\(Int(StickyAppearance.minZoom * 100))%").font(.caption)
                } maximumValueLabel: {
                    Text("\(Int(StickyAppearance.maxZoom * 100))%").font(.caption)
                }
                Text("Opens the canvas at \(Int(viewModel.initialZoomScale * 100))%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Grid Snap") {
                Stepper(value: numericBinding(\.gridSnapInterval), in: 0...200, step: 5) {
                    Text(viewModel.gridSnapInterval > 0
                         ? "Interval: \(Int(viewModel.gridSnapInterval)) pt"
                         : "Off")
                }
                Text("Snaps sticky create / move / resize to the grid. 0 = off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // A Stepper/Slider writes its current value back to the binding on re-render, not only on a
    // user change — guard the same-value write-back so a redraw never marks the form dirty
    // (the arch-presentation Picker write-back pattern, applied to numeric controls).
    private func numericBinding(_ keyPath: ReferenceWritableKeyPath<SettingsViewModel, Double>) -> Binding<Double> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { newValue in
                guard newValue != viewModel[keyPath: keyPath] else { return }
                viewModel[keyPath: keyPath] = newValue
                viewModel.markDirty()
            }
        )
    }

    /// The default sticky text colour as a hex `String`. Always a concrete colour (the "auto"
    /// sentinel is retired); the setter guards same-value write-backs so a redraw never marks the
    /// form dirty.
    private var defaultTextColorHexBinding: Binding<String> {
        Binding(
            get: { viewModel.defaultStickyTextColorHex },
            set: { newHex in
                guard newHex.caseInsensitiveCompare(viewModel.defaultStickyTextColorHex) != .orderedSame else { return }
                viewModel.defaultStickyTextColorHex = newHex
                viewModel.markDirty()
            }
        )
    }
}

// MARK: - Sticky-preset row

/// One editable preset laid out as a single horizontal row: colour well at the left, the
/// label / width / height text fields right-aligned in the middle, and the delete button at the
/// right — both icons vertically centred on the main control row. Width/height are entered as free
/// text (not a stepper); a non-numeric or out-of-range value shows a red message under the control
/// row and is not committed, so the persisted preset keeps its last valid size. The size text lives
/// in local `@State`, committed to the ViewModel only while valid.
///
/// FRAGILE PREMISE: `@State` is seeded from `preset` **once** (at `init`) and re-seeded only when
/// the row's identity changes. This is correct today because the only external mutation of a preset
/// is `resetPresets()`, which mints fresh ids → new `ForEach` identity → row re-created → re-seeded.
/// If a future path edits a preset's width/height **while keeping its id** (e.g. a "normalise sizes"
/// action), the text fields would not re-sync and would show stale values — at that point switch to
/// a binding that reads the live value, or key the `@State` on the value too.
private struct StickyPresetRowView: View {
    let viewModel: SettingsViewModel
    let preset: SettingsViewModel.EditablePreset
    @State private var widthText: String
    @State private var heightText: String

    init(viewModel: SettingsViewModel, preset: SettingsViewModel.EditablePreset) {
        self.viewModel = viewModel
        self.preset = preset
        _widthText = State(initialValue: String(Int(preset.width)))
        _heightText = State(initialValue: String(Int(preset.height)))
    }

    private var widthValid: Bool { isValid(widthText, min: StickyAppearance.minStickyWidth) }
    private var heightValid: Bool { isValid(heightText, min: StickyAppearance.minStickyHeight) }

    var body: some View {
        // One preset = one vertical group: the main control row (colour icon + inputs + trash icon)
        // on top, the optional red validation messages stacked below. Both icons live *inside* the
        // control HStack, so they centre on that row's height alone — an error appearing below grows
        // the group downward without dragging either icon off centre. `.labelsHidden()` keeps the
        // Form's auto label column from swallowing the TextField title (the old "La-/bel" wrap); the
        // size fields carry no title at all, only a placeholder + a trailing "px" suffix.
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .center, spacing: 12) {
                PaletteColorPicker(selection: colorHexBinding)
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    TextField("Label", text: labelBinding)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    dimensionField(placeholder: "Width", text: $widthText)
                    dimensionField(placeholder: "Height", text: $heightText)
                }
                Button(role: .destructive) {
                    viewModel.deletePreset(preset.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this preset")
                .padding(.leading, 8)
            }
            if !widthValid {
                rangeMessage(min: Int(StickyAppearance.minStickyWidth), label: "Width")
            }
            if !heightValid {
                rangeMessage(min: Int(StickyAppearance.minStickyHeight), label: "Height")
            }
        }
        .padding(.vertical, 2)
        .onChange(of: widthText) { _, _ in
            if widthValid, let value = Double(widthText.trimmingCharacters(in: .whitespaces)) {
                viewModel.setPresetWidth(value, for: preset.id)
            }
        }
        .onChange(of: heightText) { _, _ in
            if heightValid, let value = Double(heightText.trimmingCharacters(in: .whitespaces)) {
                viewModel.setPresetHeight(value, for: preset.id)
            }
        }
    }

    private func dimensionField(placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
            Text("px").foregroundStyle(.secondary)
        }
    }

    private func rangeMessage(min: Int, label: String) -> some View {
        Text("\(label): enter a number from \(min) to \(Int(StickyAppearance.maxPresetDimension))")
            .font(.caption2)
            .foregroundStyle(.red)
    }

    /// Numeric + range check, mirroring the Domain `StickyPreset` clamp (`min…maxDimension`).
    private func isValid(_ text: String, min: Double) -> Bool {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)) else { return false }
        return value >= min && value <= StickyAppearance.maxPresetDimension
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { preset.label },
            set: { viewModel.setPresetLabel($0, for: preset.id) }
        )
    }

    private var colorHexBinding: Binding<String> {
        Binding(
            get: { preset.colorHex },
            set: { viewModel.setPresetColor($0, for: preset.id) }
        )
    }
}
