import SwiftUI

struct SettingsContainerView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: scopeSelection) {
                Section("Scope") {
                    ForEach(viewModel.scopes, id: \.self) { scope in
                        Label(
                            viewModel.scopeTitle(scope),
                            systemImage: scope == .template ? "star" : "rectangle.stack"
                        )
                        .tag(scope)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 240)
        } detail: {
            detail
        }
        .task { viewModel.prepareInitialScope() }
        .task(id: viewModel.selectedScope) {
            await viewModel.load()
        }
        // Inject the live in-progress palette so every colour-picking control in the settings
        // subtree reads from @Environment(\.colorPalette) without explicit prop-drilling.
        .environment(\.colorPalette, viewModel.colorPaletteResponses)
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "")
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            // The TabView only carries the tab-selection chrome; each tab's heavy body (a Form full
            // of native `ColorPicker`/`NSColorWell` instances) is gated behind `LazySettingsTab` so
            // SwiftUI never instantiates the three inactive tabs' controls. The standard `TabView`
            // eagerly builds every child — for the settings window that meant ~all four tabs' colour
            // wells were allocated the moment the window opened, spiking residency to 300-800MB
            // (ticket 1AF2C8DA). Gating the bodies removes ~75% of those wells up front.
            TabView(selection: $viewModel.selectedTab) {
                LazySettingsTab(tab: .global, selected: viewModel.selectedTab) {
                    GlobalSettingsTabView(viewModel: viewModel)
                }
                .tabItem { Label("Global", systemImage: "paintbrush") }
                .tag(SettingsViewModel.Tab.global)
                LazySettingsTab(tab: .board, selected: viewModel.selectedTab) {
                    BoardSettingsTabView(viewModel: viewModel)
                }
                .tabItem { Label("Board", systemImage: "rectangle.3.group") }
                .tag(SettingsViewModel.Tab.board)
                LazySettingsTab(tab: .canvas, selected: viewModel.selectedTab) {
                    CanvasSettingsTabView(viewModel: viewModel)
                }
                .tabItem { Label("Canvas", systemImage: "note.text") }
                .tag(SettingsViewModel.Tab.canvas)
                LazySettingsTab(tab: .markdown, selected: viewModel.selectedTab) {
                    MarkdownSettingsTabView(viewModel: viewModel)
                }
                .tabItem { Label("Markdown", systemImage: "doc.richtext") }
                .tag(SettingsViewModel.Tab.markdown)
            }
            .padding(.top, 12)

            Divider()

            footer
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to Defaults") {
                Task { await viewModel.resetActiveTab() }
            }
            .disabled(!viewModel.canResetActiveTab)

            Spacer()

            Button("Save") {
                Task { await viewModel.save() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.isDirty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// `List(selection:)` needs an optional binding; ignore a nil (deselect) so a scope always
    /// stays chosen.
    private var scopeSelection: Binding<SettingsViewModel.Scope?> {
        Binding(
            get: { viewModel.selectedScope },
            set: { if let scope = $0 { viewModel.selectedScope = scope } }
        )
    }
}

// MARK: - Lazy tab body gate

/// Renders its tab body only while the tab is the selected one, keeping the `tabItem` chrome present
/// for the unselected tabs (so the tab bar is unchanged) while skipping the body's view tree. This
/// defers the native `ColorPicker`/`NSColorWell` allocations in the three inactive settings tabs
/// until the user actually switches to them (ticket 1AF2C8DA). The body is rebuilt each time the tab
/// is re-selected — acceptable here since a tab body is cheap to reconstruct and its persistent state
/// lives on the shared `SettingsViewModel`, not in transient view `@State`.
private struct LazySettingsTab<Content: View>: View {
    let tab: SettingsViewModel.Tab
    let selected: SettingsViewModel.Tab
    @ViewBuilder let content: () -> Content

    var body: some View {
        if tab == selected {
            content()
        } else {
            Color.clear
        }
    }
}
