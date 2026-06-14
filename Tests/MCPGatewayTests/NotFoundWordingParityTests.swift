import XCTest
@testable import KanvasCore

/// Pins the cross-type wording parity the gateway relies on (ticket 0D2DE256): a stale id must read
/// identically to the model whether the typed MCP pre-check (`KanvasMCPError.notFound`) or the
/// domain backstop (`OperationError.notFound`) fires. Both render `"<kind> not found: <id>"`, but
/// the two enums live in separate layers — only this test keeps the formats from silently drifting.
final class NotFoundWordingParityTests: XCTestCase {

    func testNotFound_mcpAndDomainRenderIdentically() {
        let id = UUID()
        XCTAssertEqual(
            KanvasMCPError.notFound(kind: "Connector", id: id.uuidString).description,
            OperationError.notFound(entityKind: "Connector", id: id).errorDescription
        )
    }
}
