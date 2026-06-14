import SwiftUI

/// Settings → Markdown tab: base font size + monospaced toggle, per-level heading sizes, and the
/// inline-code / blockquote colours. Lives in its own file (rather than `private` inside
/// `SettingsContainerView`) to keep that file within the line-length budget.
struct MarkdownSettingsTabView: View {
    @Bindable var viewModel: SettingsViewModel

    // Footer copy extracted to named constants so the source lines stay within the 120-column
    // line-length budget (was a swiftlint:disable:next line_length on each inline literal).
    private static let syntaxColorsFooter = """
        A custom color applies to both light and dark mode; the swatch previews the light default. \
        Diff line backgrounds are set separately below.
        """

    private static let diffLineBackgroundsFooter = """
        The full-width background fill behind added / removed diff lines, independent of the text \
        color. The built-in default differs by appearance, so the cleared preview shows both the \
        light and dark swatches. A custom color applies to both light and dark mode.
        """

    var body: some View {
        Form {
            Section("Base Font") {
                Stepper(value: numericBinding(\.markdownBaseFontSize),
                        in: MarkdownAppearance.minBaseFontSize...MarkdownAppearance.maxBaseFontSize, step: 1) {
                    Text("Size: \(Int(viewModel.markdownBaseFontSize)) pt")
                }
                Toggle("Use monospaced font", isOn: monospacedBinding)
            }

            Section("Heading Sizes") {
                ForEach(viewModel.markdownHeadingSizes.indices, id: \.self) { level in
                    Stepper(value: headingBinding(level),
                            in: MarkdownAppearance.minHeadingSize...MarkdownAppearance.maxHeadingSize, step: 1) {
                        Text("H\(level + 1): \(Int(viewModel.markdownHeadingSizes[level])) pt")
                    }
                }
            }

            Section("Code Color") {
                ClearablePaletteColorPicker(
                    selection: $viewModel.markdownCodeColorHex,
                    defaultColor: Color(hex: MarkdownAppearance.codeDefaultHex),
                    title: "Inline Code",
                    onEdit: { viewModel.markDirty() }
                )
            }

            Section("Quote Color") {
                ClearablePaletteColorPicker(
                    selection: $viewModel.markdownQuoteColorHex,
                    defaultColor: Color(hex: MarkdownAppearance.quoteDefaultHex),
                    title: "Blockquote Text",
                    onEdit: { viewModel.markDirty() }
                )
            }

            Section("Code Block Background") {
                ClearablePaletteColorPicker(
                    selection: $viewModel.markdownCodeBlockBackgroundColorHex,
                    defaultColor: Color(hex: MarkdownAppearance.codeBlockBackgroundDefaultHex),
                    title: "Code Block Background",
                    onEdit: { viewModel.markDirty() }
                )
            }

            Section("Blockquote Border") {
                ClearablePaletteColorPicker(
                    selection: $viewModel.markdownQuoteBorderColorHex,
                    defaultColor: Color(hex: MarkdownAppearance.quoteBorderDefaultHex),
                    title: "Border Color",
                    onEdit: { viewModel.markDirty() }
                )
                Stepper(value: numericBinding(\.markdownQuoteBorderWidth),
                        in: MarkdownAppearance.minQuoteBorderWidth...MarkdownAppearance.maxQuoteBorderWidth,
                        step: 1) {
                    Text("Border Width: \(Int(viewModel.markdownQuoteBorderWidth)) pt")
                }
            }

            Section("Link Color") {
                ClearablePaletteColorPicker(
                    selection: $viewModel.markdownLinkColorHex,
                    defaultColor: Color(hex: MarkdownAppearance.linkDefaultHex),
                    title: "Links",
                    onEdit: { viewModel.markDirty() }
                )
            }

            Section("Editor Background") {
                ClearablePaletteColorPicker(
                    selection: $viewModel.markdownEditorBackgroundColorHex,
                    defaultColor: Color(.textBackgroundColor),
                    title: "Background",
                    onEdit: { viewModel.markDirty() }
                )
            }

            Section {
                ForEach(MarkdownAppearance.syntaxTokenDescriptors) { token in
                    ClearablePaletteColorPicker(
                        selection: syntaxOverrideBinding(token.key),
                        defaultColor: Color(hex: token.defaultLightHex),
                        title: token.label,
                        onEdit: { viewModel.markDirty() }
                    )
                }
            } header: {
                Text("Code Syntax Colors")
            } footer: {
                Text(Self.syntaxColorsFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(MarkdownAppearance.lineBackgroundDescriptors) { descriptor in
                    ClearablePaletteColorPicker(
                        selection: syntaxOverrideBinding(descriptor.key),
                        defaultColor: Color(hex: descriptor.defaultLightHex),
                        defaultDarkColor: Color(hex: descriptor.defaultDarkHex),
                        title: descriptor.label,
                        onEdit: { viewModel.markDirty() }
                    )
                }
            } header: {
                Text("Diff Line Backgrounds")
            } footer: {
                Text(Self.diffLineBackgroundsFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Paragraph Spacing") {
                Stepper(value: numericBinding(\.markdownLineSpacing),
                        in: 0...MarkdownAppearance.maxLineSpacing, step: 1) {
                    Text("Line Spacing: \(Int(viewModel.markdownLineSpacing)) pt")
                }
                Stepper(value: numericBinding(\.markdownListItemSpacing),
                        in: 0...MarkdownAppearance.maxListItemSpacing, step: 1) {
                    Text("List Item Spacing: \(Int(viewModel.markdownListItemSpacing)) pt")
                }
                Stepper(value: numericBinding(\.markdownListIndentExtra),
                        in: 0...MarkdownAppearance.maxListIndentExtra, step: 2) {
                    Text("List Indent Extra: \(Int(viewModel.markdownListIndentExtra)) pt")
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // A Stepper writes its current value back to the binding on re-render, not only on a user
    // change — guard the same-value write-back so a redraw never marks the form dirty (the
    // arch-presentation Picker write-back pattern, applied to numeric controls).
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

    /// One element of the heading-sizes array, guarded against same-value write-back.
    private func headingBinding(_ level: Int) -> Binding<Double> {
        Binding(
            get: { viewModel.markdownHeadingSizes[level] },
            set: { newValue in
                guard newValue != viewModel.markdownHeadingSizes[level] else { return }
                viewModel.markdownHeadingSizes[level] = newValue
                viewModel.markDirty()
            }
        )
    }

    /// Bridges one token kind's entry in the `markdownSyntaxColorOverrides` map to a `String?`
    /// binding for `ClearablePaletteColorPicker`: a present hex = override set, `nil` = cleared
    /// (removes the key so it inherits the built-in palette). Dirty-marking is left to the
    /// picker's `onEdit:` (matching every sibling tab's plain-binding + `onEdit` pattern), so a
    /// real change marks the form dirty exactly once.
    private func syntaxOverrideBinding(_ key: String) -> Binding<String?> {
        Binding(
            get: { viewModel.markdownSyntaxColorOverrides[key] },
            set: { newValue in
                if let newValue {
                    viewModel.markdownSyntaxColorOverrides[key] = newValue
                } else {
                    viewModel.markdownSyntaxColorOverrides.removeValue(forKey: key)
                }
            }
        )
    }

    private var monospacedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.markdownUseMonospacedFont },
            set: { newValue in
                guard newValue != viewModel.markdownUseMonospacedFont else { return }
                viewModel.markdownUseMonospacedFont = newValue
                viewModel.markDirty()
            }
        )
    }
}
