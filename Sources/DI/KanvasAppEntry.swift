import SwiftUI

/// The `Kanvas` executable's entry into KanvasCore. Lives in DI — the composition root is the one
/// layer that may name `Container` — so Presentation (`KanvasRootScene`) stays free of DI
/// references and receives its ViewModel + factory by injection. Mirrors `KanvasMCP.makeGateway()`
/// on the MCP side: each executable gets exactly one public entry point.
public enum KanvasAppEntry {
    /// `copyToPasteboard` is created in `Sources/App/` (the only AppKit zone) and passed in so
    /// DI and Presentation never import AppKit. `@MainActor` because NSPasteboard is a
    /// main-thread API; returns whether the write succeeded.
    @MainActor
    public static func makeRootScene(
        copyToPasteboard: @escaping @MainActor (String) -> Bool
    ) -> some Scene {
        let container = Container.shared
        return KanvasRootScene(
            boardViewModel: container.makeBoardViewModel(),
            makeSettingsViewModel: { container.makeSettingsViewModel(boardViewModel: $0) },
            copyToPasteboard: copyToPasteboard
        )
    }
}
