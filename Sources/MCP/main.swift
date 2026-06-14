import Foundation
import KanvasCore
import MCP

// Kanvas MCP server: gives a model Read/Write access to Board / Canvas / Markdown by driving the
// KanvasCore UseCase layer (via `KanvasMCPGateway`) over stdio. The gateway and all use cases run
// the same product code as the app; cross-process writes are serialized by the store's file lock,
// and the running app live-refreshes via its store watcher.

let gateway = KanvasMCP.makeGateway()

let tools: [any MCPTool] = boardTools(gateway) + canvasTools(gateway) + markdownTools(gateway)
let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

let server = Server(
    name: "kanvas-mcp",
    version: "0.1.0",
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: tools.map(\.definition))
}

await server.withMethodHandler(CallTool.self) { params in
    guard let tool = toolsByName[params.name] else {
        return CallTool.Result(
            content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)],
            isError: true
        )
    }
    do {
        return try await tool.execute(params.arguments ?? [:])
    } catch {
        return CallTool.Result(
            content: [.text(text: errorText(error), annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()

/// Readable message for the model: prefer a `LocalizedError`'s description (e.g. `OperationError`),
/// else the raw value (our `CustomStringConvertible` argument/gateway errors describe themselves).
func errorText(_ error: any Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return String(describing: error)
}
