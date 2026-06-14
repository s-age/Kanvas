import SwiftUI

// MARK: - Reusable palette colour picker

/// A palette colour picker. Selection is **palette-only** — there is no OS `ColorPicker` escape
/// hatch here, so this control never mints an `NSColorWell` and never triggers the OS colour-picker
/// subsystem's ~500MB first-load (ticket 3D74A415). Defining a new colour lives solely in the Global
/// tab's palette rows; everywhere else picks from the palette.
///
/// **Shared-popover layout (ticket 5EA3E652).** Each control renders a **single current-colour
/// button** rather than an inline `ForEach` of all palette swatches. Tapping the button opens a
/// **one** swatch grid in a `.popover`; the grid materialises its swatch sub-tree only while open and
/// is torn down on dismiss. Previously every control eagerly materialised the full N-swatch row, so
/// `27 controls × 14 swatches = 378` swatch sub-trees (giant nested SwiftUI types + `NSView` backing
/// + `CALayer`) stayed resident at all times. Collapsing to one current-colour button per control
/// (plus, when open, one shared grid) cuts the resident swatch sub-trees by ~14×.
///
/// Two public entry points:
///
/// **Required variant** — `PaletteColorPicker(selection:)`
///   Always has a hex value. The current-colour button shows the current hex; the popover grid
///   writes the chosen swatch hex. The swatch matching the current selection (case-insensitive) gets
///   a highlight ring in the grid.
///
/// **Clearable variant** — `ClearablePaletteColorPicker(selection:defaultColor:onEdit:)`
///   `nil` means "use system default". The current-colour button shows the resolved default while
///   nil. The popover grid adds a "Clear" action and a "Using system default" caption (with built-in
///   light/dark preview swatches).
///
/// **No-fill composability note:**
/// The shape-fill site (a future phase) needs a *separate* "no fill" control whose `nil` means
/// "no fill" — a different semantic from the clearable variant's `nil` = "system default".
/// To avoid baking fill-specific semantics here, the `required` variant is the composable primitive:
/// a shape-fill toolbar can render its own "no fill" button **beside** a `PaletteColorPicker`
/// (required, with a non-optional binding). This keeps the two `nil` meanings in separate
/// controls at the call site and this component stays free of fill-specific logic.
///
/// Type-erasing wrappers are forbidden by SwiftLint. The two variants are separate `View` structs
/// so each has its own concrete `body` return type.
struct PaletteColorPicker: View {
    @Binding var selection: String
    /// Optional leading label. Omit for a bare swatch button.
    let title: String?
    @State private var popoverShown = false

    init(selection: Binding<String>, title: String? = nil) {
        self._selection = selection
        self.title = title
    }

    var body: some View {
        HStack(spacing: 6) {
            if let title {
                Text(title)
                Spacer(minLength: 8)
            }
            currentColorButton(hex: selection) { popoverShown = true }
                .popover(isPresented: $popoverShown, arrowEdge: .bottom) {
                    PaletteSwatchPopover(
                        selectedHex: selection,
                        onSelect: { hex in
                            popoverShown = false
                            guard hex.caseInsensitiveCompare(selection) != .orderedSame else { return }
                            selection = hex
                        }
                    )
                }
        }
    }
}

// MARK: - Clearable variant

/// A clearable version of `PaletteColorPicker` where `nil` means "use system default".
/// Palette-only selection — no OS `ColorPicker` escape hatch, so it never mints an `NSColorWell`
/// (ticket 3D74A415). Behaviour:
///   • Shows the resolved default colour on the current-colour button while selection is nil.
///   • The popover grid offers a "Clear" action (reset to nil + `onEdit`) and a "Using system
///     default" caption (+ built-in light/dark preview swatches) while selection is nil.
///   • `onEdit` is an edit notification (e.g. `markDirty`), not the persistence channel.
struct ClearablePaletteColorPicker: View {
    @Binding var selection: String?
    let defaultColor: Color
    /// Optional dark-mode counterpart of `defaultColor`. When the built-in default differs by
    /// appearance (e.g. the diff line backgrounds, `e6ffec`/`033a16`), pass the dark hex here so the
    /// **cleared** state previews *both* built-in swatches (light + dark) instead of light only —
    /// since an absent override lets the editor paint a different shade per appearance. Omit it when
    /// the built-in default is appearance-neutral; the cleared preview then shows one swatch as
    /// before. A user override is still appearance-neutral (one hex for both modes, consistent with
    /// every other override), so this only enriches the cleared preview — it does not split the
    /// override into a pair.
    let defaultDarkColor: Color?
    /// Edit *notification* — invoked after the selection changes (swatch tap, custom pick, or
    /// clear). Not a persistence channel: callers whose binding persists on its own (e.g. a
    /// canvas object's async setter) can omit it; the settings tabs use it to `markDirty()`.
    let onEdit: () -> Void
    /// Optional leading label. Omit for a bare swatch button.
    let title: String?
    @State private var popoverShown = false
    /// The live resolution environment (colour scheme, etc.). Threaded into the current-colour
    /// button so the cleared-state chevron's contrast is computed against the resolved default for
    /// the active appearance when `defaultColor` is a dynamic system colour (ticket 1AF2C8DA r3).
    @Environment(\.self) private var environment

    init(
        selection: Binding<String?>,
        defaultColor: Color,
        defaultDarkColor: Color? = nil,
        title: String? = nil,
        onEdit: @escaping () -> Void = {}
    ) {
        self._selection = selection
        self.defaultColor = defaultColor
        self.defaultDarkColor = defaultDarkColor
        self.title = title
        self.onEdit = onEdit
    }

    var body: some View {
        HStack(spacing: 6) {
            if let title {
                Text(title)
                Spacer(minLength: 8)
            }
            currentColorButton(
                hex: selection,
                fallback: defaultColor,
                environment: environment
            ) { popoverShown = true }
                .popover(isPresented: $popoverShown, arrowEdge: .bottom) {
                    PaletteSwatchPopover(
                        selectedHex: selection,
                        clearConfig: PaletteSwatchPopover.ClearConfig(
                            isCleared: selection == nil,
                            defaultColor: defaultColor,
                            defaultDarkColor: defaultDarkColor,
                            onClear: {
                                popoverShown = false
                                selection = nil
                                onEdit()
                            }
                        ),
                        onSelect: { hex in
                            popoverShown = false
                            guard hex != selection else { return }
                            selection = hex
                            onEdit()
                        }
                    )
                }
        }
    }

    /// Decides the clearable selection's next value, applying the **resolved-default** guard:
    /// while `selection == nil` the resolved value is `defaultColor`, and a re-emitted
    /// same-as-default write must not silently bake a "use system default" selection into an
    /// explicit per-element colour. Returns `nil` to mean "skip the write" (a no-op).
    ///
    /// **Currently production-dead — kept intentionally.** The only caller that wrote through this
    /// guard was the OS colour well removed in ticket 3D74A415, so no live control feeds it today;
    /// it survives only via its unit tests. It is retained (rather than deleted with its tests)
    /// because the clearable variant is a documented composability primitive for the upcoming
    /// shape-fill phase (see the no-fill note above), whose clearable colour-write path will route
    /// through exactly this guard again — keeping it pure + `static` keeps that contract pinned and
    /// testable without a live SwiftUI binding. If that phase is dropped, delete this and its tests.
    nonisolated static func nextSelection(
        current selection: String?,
        default defaultHex: String,
        picked newHex: String
    ) -> String? {
        let resolved = selection ?? defaultHex
        return newHex.caseInsensitiveCompare(resolved) == .orderedSame ? nil : newHex
    }
}

// MARK: - Shared swatch popover

/// The shared swatch grid shown in a `.popover` from a colour control's current-colour button. It
/// reads the palette from `@Environment(\.colorPalette)` and materialises its swatch sub-tree only
/// while open — the crux of ticket 5EA3E652: instead of every control keeping a full N-swatch row
/// resident, a single grid is built on demand and freed on dismiss.
///
/// Required controls pass only `onSelect`. Clearable controls additionally pass a `ClearConfig`
/// carrying the cleared state, the built-in default(s) to preview, and the clear action — so the
/// grid renders a "Clear" / "Using system default" footer with the built-in light/dark preview
/// swatches.
struct PaletteSwatchPopover: View {
    /// The current selection hex, or `nil` for the clearable variant's "use system default" state.
    /// Used to ring the matching swatch in the grid.
    let selectedHex: String?
    /// Present only for the clearable variant; drives the Clear footer + system-default preview.
    let clearConfig: ClearConfig?
    /// Invoked with the chosen palette swatch hex.
    let onSelect: (String) -> Void
    @Environment(\.colorPalette) private var palette

    /// Per-row swatch count for the grid layout.
    private static let columns = 6

    init(
        selectedHex: String?,
        clearConfig: ClearConfig? = nil,
        onSelect: @escaping (String) -> Void
    ) {
        self.selectedHex = selectedHex
        self.clearConfig = clearConfig
        self.onSelect = onSelect
    }

    /// The clearable-variant footer configuration: the cleared flag, the built-in default(s) to
    /// preview, and the clear action.
    struct ClearConfig {
        let isCleared: Bool
        let defaultColor: Color
        let defaultDarkColor: Color?
        let onClear: () -> Void
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            grid
            if let clearConfig {
                Divider()
                clearFooter(clearConfig)
            }
        }
        .padding(12)
    }

    // MARK: - Sub-views

    private var grid: some View {
        let layout = Array(
            repeating: GridItem(.fixed(20), spacing: 6),
            count: Self.columns
        )
        return LazyVGrid(columns: layout, alignment: .leading, spacing: 6) {
            ForEach(palette) { swatch in
                let isSelected = swatch.colorHex.caseInsensitiveCompare(selectedHex ?? "") == .orderedSame
                paletteSwatchButton(hex: swatch.colorHex, label: swatch.label, isSelected: isSelected) {
                    onSelect(swatch.colorHex)
                }
            }
        }
        .frame(width: CGFloat(Self.columns) * 26)
    }

    /// The clearable variant's footer: a "Clear" button plus a "Using system default" caption with
    /// the built-in light (and optionally dark) preview swatches shown while cleared.
    @ViewBuilder
    private func clearFooter(_ config: ClearConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Clear", action: config.onClear)
                .font(.caption)
                .disabled(config.isCleared)
            if config.isCleared {
                if let defaultDarkColor = config.defaultDarkColor {
                    HStack(spacing: 6) {
                        Text("Using system default")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        defaultPreviewSwatch(color: config.defaultColor, label: "Light")
                        defaultPreviewSwatch(color: defaultDarkColor, label: "Dark")
                    }
                } else {
                    Text("Using system default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A small non-interactive swatch + appearance label for a built-in default in the cleared
    /// preview. Mirrors the swatch-button look without the selection ring or tap action.
    private func defaultPreviewSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            swatchSquare(fill: color, side: 14, cornerRadius: 3)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .help("Built-in \(label.lowercased())-mode default")
    }
}

// MARK: - Current-colour button helper

/// The single resting control each colour picker shows in place of the old inline swatch row: a
/// swatch filled with the current colour that opens the shared swatch popover on tap. For the
/// clearable variant a `nil` selection falls back to the resolved `fallback` (the built-in default)
/// so the button always previews what the editor actually paints.
@MainActor
private func currentColorButton(
    hex: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        swatchSquare(fill: Color(hex: hex))
            .overlay {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.readableForeground(onHex: hex))
                    .offset(y: 6)
            }
    }
    .buttonStyle(.plain)
    .help("Choose color")
}

/// Clearable overload: when `hex` is nil the button previews the resolved `fallback` default.
///
/// The chevron glyph derives a readable black/white foreground against the **actual fill** in both
/// states — the current hex when set, and the resolved `fallback` when cleared. The cleared case
/// resolves against the live `environment` because `fallback` may be a dynamic system colour (e.g.
/// `.boardDefaultBackground`), whose contrast differs by appearance; an empty environment would
/// always pick the light variant and mis-contrast in dark mode (ticket 1AF2C8DA r3).
@MainActor
private func currentColorButton(
    hex: String?,
    fallback: Color,
    environment: EnvironmentValues,
    action: @escaping () -> Void
) -> some View {
    let fill = hex.map { Color(hex: $0) } ?? fallback
    let foreground = hex.map { Color.readableForeground(onHex: $0) }
        ?? Color.readableForeground(onColor: fill, in: environment)
    return Button(action: action) {
        swatchSquare(fill: fill)
            .overlay {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(foreground)
                    .offset(y: 6)
            }
    }
    .buttonStyle(.plain)
    .help("Choose color")
}

// MARK: - Shared swatch-square helper

/// The base swatch look shared by every swatch site here (palette swatches, the cleared-default
/// preview, and the current-colour button): a colour-filled rounded square with a subtle border.
/// Callers layer selection rings, checkmarks, or glyphs on top via `.overlay`. Keeping the fill +
/// border in one place means a tweak to the resting look stays in sync everywhere.
@MainActor
private func swatchSquare(fill: Color, side: CGFloat = 20, cornerRadius: CGFloat = 4) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius)
        .fill(fill)
        .frame(width: side, height: side)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.5)
        )
}

// MARK: - Shared swatch button helper

/// Small rounded-square swatch matching the `ShapeToolbarView` look: a filled square with a subtle
/// border, a readable-foreground checkmark when selected, and an accent selection ring.
@MainActor
private func paletteSwatchButton(
    hex: String,
    label: String,
    isSelected: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        swatchSquare(fill: Color(hex: hex))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                    .padding(-2)
            )
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.readableForeground(onHex: hex))
                }
            }
    }
    .buttonStyle(.plain)
    .help(label)
}

// MARK: - Lazy colour well

/// A native colour well, but **deferred**. A native `ColorPicker` (an `NSColorWell` under the hood)
/// is a heavy control: when the settings window mints dozens at once (one per labelled row + one per
/// palette/column/token/preset entry) residency spikes into the hundreds of MB the moment the window
/// opens (ticket 1AF2C8DA). To avoid that, this renders a lightweight swatch *button* first; only
/// once the user taps it (`activated == true`) does it swap in the real `ColorPicker`.
///
/// The placeholder button shows the current colour like the resting well, **plus an eyedropper glyph
/// overlay** so it reads as "open a colour editor" rather than as just another selectable palette
/// swatch.
/// Tapping it flips `activated`; for the rest of that tab visit the row keeps the live well, so every
/// subsequent edit is the usual one-tap-to-open-panel interaction. The trade-off is that the very
/// first edit is two taps (reveal the well, then open the panel); the editor is only ever opened to
/// tweak an existing palette entry, an occasional action, so the cost is acceptable.
///
/// `activated` is **per-tab-visit, not window-lifetime** state. `LazySettingsTab` renders
/// `Color.clear` for unselected tabs, so switching away tears down this view subtree — including the
/// transient `@State activated` — and re-selecting rebuilds it with `activated == false` (the first
/// edit is two taps again). That is the same deliberate trade-off `LazySettingsTab` makes to defer
/// the heavy `NSColorWell` allocations off the inactive tabs; persistent state lives on
/// `SettingsViewModel`, never in this transient `@State`.
///
/// `help` labels both states (the placeholder button and the live well) so the call site names the
/// control accurately — e.g. "Edit color" for the Global tab's palette-entry editor, the sole caller.
/// The bound colour and its write-back guards live entirely in the parent's binding, so this view
/// changes only *when* the well is built, never the edit behaviour.
struct LazyColorWell: View {
    @Binding var selection: Color
    /// Tooltip + accessibility help for both the placeholder button and the live well. The call site
    /// supplies it so the label fits the role (currently only the Global tab's palette-entry editor).
    let help: String
    @State private var activated = false
    /// The live resolution environment (colour scheme, etc.). Needed so a dynamic system `selection`
    /// (e.g. `.boardDefaultBackground`) resolves to the *displayed* shade when sizing the eyedropper
    /// glyph's contrast — an empty environment always yields the light variant (ticket 1AF2C8DA r3).
    @Environment(\.self) private var environment

    var body: some View {
        if activated {
            ColorPicker("", selection: $selection, supportsOpacity: false)
                .labelsHidden()
                .help(help)
        } else {
            Button {
                activated = true
            } label: {
                swatchSquare(fill: selection)
                    .overlay {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.readableForeground(onColor: selection, in: environment))
                    }
            }
            .buttonStyle(.plain)
            .help(help)
        }
    }
}
