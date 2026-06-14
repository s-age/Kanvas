import AppKit
import KanvasCore
import SwiftUI

@main
struct KanvasApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppBootstrap

    // The whole scene graph lives in `KanvasRootScene` (KanvasCore); DI's `KanvasAppEntry` wires
    // it so the same product code backs both this app and the MCP server. The factory is
    // idempotent (the container caches the board VM), so `body` re-evaluation is safe.
    var body: some Scene {
        // NSPasteboard lives in AppKit, so the closure is created here — the only zone where
        // AppKit is permitted — and injected down so Presentation stays AppKit-free.
        KanvasAppEntry.makeRootScene {
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString($0, forType: .string)
        }
    }
}
