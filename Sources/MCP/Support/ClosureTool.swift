import MCP

/// A concrete `MCPTool` whose behaviour is a closure over `KanvasMCPGateway`. Every Kanvas tool is
/// the same shape — parse args, call one gateway method, return its JSON — so one parameterized
/// type beats 19 near-identical structs. The handler returns the JSON string the gateway produced.
struct ClosureTool: MCPTool {
    let name: String
    let description: String
    let inputSchema: Value
    let handler: @Sendable (Arguments) async throws -> String

    func execute(_ arguments: [String: Value]) async throws -> CallTool.Result {
        text(try await handler(Arguments(arguments)))
    }
}

/// Builds a JSON-Schema `object` from `(name, type, description, required)` property tuples.
/// Keeps each tool's schema a one-liner instead of a nested `Value` literal.
func objectSchema(_ properties: [(name: String, type: String, description: String, required: Bool)]) -> Value {
    var props: [String: Value] = [:]
    var required: [Value] = []
    for property in properties {
        props[property.name] = .object([
            "type": .string(property.type),
            "description": .string(property.description),
        ])
        if property.required { required.append(.string(property.name)) }
    }
    return ["type": "object", "properties": .object(props), "required": .array(required)]
}
