import SwiftUI

/// The app's whole SwiftUI scene graph. The `Kanvas` executable obtains it via
/// `KanvasAppEntry.makeRootScene()` (DI) — the ViewModel and the settings-VM factory arrive by
/// injection, so this file references no DI type and Presentation's import boundary holds.
/// Plain `let` storage: the factory is idempotent (`Container` caches the board VM), so every
/// scene re-evaluation injects the same instance and `@Observable` handles observation.
struct KanvasRootScene: Scene {
    private let boardViewModel: BoardViewModel
    /// Mints the settings VM for the auxiliary window — DI-hosted so this scene never names a
    /// use case or the container (see arch-di "DI-hosted factory closures").
    private let makeSettingsViewModel: @MainActor (BoardViewModel) -> SettingsViewModel
    /// Writes a string to the system pasteboard, returning whether the write succeeded. Created
    /// in `Sources/App/` (the only AppKit-permitted zone) and injected here so Presentation never
    /// imports AppKit directly; `@MainActor` because NSPasteboard is a main-thread API.
    private let copyToPasteboard: @MainActor (String) -> Bool

    init(
        boardViewModel: BoardViewModel,
        makeSettingsViewModel: @escaping @MainActor (BoardViewModel) -> SettingsViewModel,
        copyToPasteboard: @escaping @MainActor (String) -> Bool
    ) {
        self.boardViewModel = boardViewModel
        self.makeSettingsViewModel = makeSettingsViewModel
        self.copyToPasteboard = copyToPasteboard
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: boardViewModel, copyToPasteboard: copyToPasteboard)
        }
        // One board window only. The single shared `boardViewModel` is not built for
        // multiple WindowGroup windows, and the settings↔board lifetime coupling below
        // assumes a 1:1 relationship — so drop the automatic File ▸ New Window (⌘N) item.
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        Window("Board Settings", id: WindowID.settings) {
            SettingsWindowContent(boardViewModel: boardViewModel, makeViewModel: makeSettingsViewModel)
        }
        .defaultSize(width: 520, height: 440)
        // The settings window is an auxiliary `Window` scene. If it is left open at quit,
        // macOS scene restoration reopens *only* it on next launch and suppresses the main
        // WindowGroup window — so kanvas comes up showing nothing but settings. Excluding
        // the scene from restoration makes the main window come up normally every time.
        // (Closing the window in `applicationShouldTerminate` does NOT work: SwiftUI records
        // the scene's restoration state before that close runs.)
        .restorationBehavior(.disabled)

        // The single reusable Markdown image-preview window (ticket 8511D150). A `Window(id:)`
        // (not a `WindowGroup`) so a second thumbnail tap re-targets the same window's content
        // instead of spawning another. It reads its target from `boardViewModel.markdownImagePreview`
        // (shared state, since a `Window` scene takes no `openWindow` payload) and re-loads the asset
        // bytes itself. `MarkdownImageViewer` resizes the window to the image's aspect-fit initial
        // size on load, so the static `.defaultSize` is only a pre-load placeholder.
        Window("Image Preview", id: WindowID.markdownImagePreview) {
            MarkdownImageViewer(viewModel: boardViewModel)
        }
        .defaultSize(width: 640, height: 480)
        .restorationBehavior(.disabled)
    }
}

private struct ContentView: View {
    let viewModel: BoardViewModel
    let copyToPasteboard: @MainActor (String) -> Bool
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        NavigationStack {
            KanbanBoardView(viewModel: viewModel, copyToPasteboard: copyToPasteboard)
                .navigationDestination(isPresented: Binding(
                    get: { viewModel.selectedCardID != nil },
                    set: { if !$0 { viewModel.selectedCardID = nil } }
                )) {
                    CardDetailView(viewModel: viewModel)
                }
        }
        .frame(minWidth: 900, minHeight: 600)
        // The settings window is an independent `Window` scene, so closing the main board
        // window leaves it orphaned — the app stays alive showing only settings. Tie its
        // lifetime to the main window: when this view's window closes, dismiss settings too.
        .onDisappear {
            dismissWindow(id: WindowID.settings)
        }
    }
}

private struct SettingsWindowContent: View {
    @State private var viewModel: SettingsViewModel

    init(boardViewModel: BoardViewModel, makeViewModel: @MainActor (BoardViewModel) -> SettingsViewModel) {
        _viewModel = State(initialValue: makeViewModel(boardViewModel))
    }

    var body: some View {
        SettingsContainerView(viewModel: viewModel)
    }
}
