import MCP

/// A single MCP tool: its advertised schema plus the logic that runs on call. Mirrors the
/// your-usual `swift-mcp` pattern — one value owns both its `Tool` definition (for `tools/list`)
/// and its `execute` (for `tools/call`). Each tool is a thin wrapper over `KanvasMCPGateway`.
protocol MCPTool: Sendable {
    /// Stable tool name exposed to the client (e.g. `board_card_add`).
    var name: String { get }
    /// Human-facing description.
    var description: String { get }
    /// JSON Schema for the tool arguments, as an MCP `Value`.
    var inputSchema: Value { get }
    /// Run the tool. Throws for user-facing failures (surfaced as an `isError` text result).
    func execute(_ arguments: [String: Value]) async throws -> CallTool.Result
}

extension MCPTool {
    /// The `Tool` definition advertised in `tools/list`.
    var definition: Tool {
        Tool(name: name, description: description, inputSchema: inputSchema)
    }

    /// Wrap a plain string (the gateway's JSON) as a successful text result.
    func text(_ string: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: string, annotations: nil, _meta: nil)])
    }
}
