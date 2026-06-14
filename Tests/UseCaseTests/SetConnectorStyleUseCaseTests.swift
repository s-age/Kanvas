import XCTest
@testable import KanvasCore

/// `SetConnectorStyleUseCaseImpl` over the real repository + service. Pins the property that justifies
/// its existence next to the four single-field setters: a multi-field edit validates **all**
/// provided fields before anything commits — an invalid late field can never leave the early
/// fields partially applied (the failure mode of chaining the single-field use cases).
final class SetConnectorStyleUseCaseTests: XCTestCase {

    private let cardID = UUID()
    private let connectorID = UUID()
    private var repository: BoardRepository!
    private var useCase: SetConnectorStyleUseCaseImpl!

    override func setUp() {
        super.setUp()
        let source = Sticky(id: UUID(), cardID: cardID, content: "a", position: .zero, sortIndex: 0)
        let target = Sticky(id: UUID(), cardID: cardID, content: "b", position: .zero, sortIndex: 1)
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [source, target])
        state.connectors = [Connector(
            id: connectorID, cardID: cardID,
            sourceStickyID: source.id, sourceEdge: .right,
            targetStickyID: target.id, targetEdge: .left
        )]
        repository = BoardRepository(store: InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(state)),
                                     diagnostics: SpyDiagnosticsLogger())
        let connectorService = ConnectorService(
            repository: repository, stickyService: StickyService(repository: repository)
        )
        useCase = SetConnectorStyleUseCaseImpl(connectorService: connectorService)
    }

    private func storedStyle() async throws -> ConnectorStyle? {
        try await repository.loadActiveBoard().connectors.first { $0.id == connectorID }?.style
    }

    func testExecute_appliesAllProvidedFields() async throws {
        _ = try await useCase.execute(SetConnectorStyleRequest(
            connectorID: connectorID, cap: "line", routing: "curve", strokeColorHex: "FF0000", strokeWidth: 5
        ))

        let style = try await storedStyle()
        XCTAssertEqual(style?.cap, .line)
        XCTAssertEqual(style?.routing, .curve)
        XCTAssertEqual(style?.strokeColorHex, "FF0000")
        XCTAssertEqual(style?.strokeWidth, 5)
    }

    func testExecute_nilFieldsKeepCurrentValues() async throws {
        _ = try await useCase.execute(SetConnectorStyleRequest(
            connectorID: connectorID, cap: nil, routing: "elbow", strokeColorHex: nil, strokeWidth: nil
        ))

        let style = try await storedStyle()
        XCTAssertEqual(style?.routing, .elbow)
        // Untouched fields keep the defaults the connector was created with.
        XCTAssertEqual(style?.cap, ConnectorStyle.default.cap)
        XCTAssertEqual(style?.strokeColorHex, ConnectorStyle.default.strokeColorHex)
        XCTAssertEqual(style?.strokeWidth, ConnectorStyle.default.strokeWidth)
    }

    func testExecute_invalidLateField_throwsAndAppliesNothing() async throws {
        // Valid cap + invalid routing: the chained single-field use cases would commit the cap
        // before routing validation throws — this use case must apply neither.
        let validatingUseCase = ValidationAsyncUseCaseDecorator(useCase!)
        await XCTAssertThrowsErrorAsync(try await validatingUseCase.execute(SetConnectorStyleRequest(
            connectorID: self.connectorID, cap: "line", routing: "zigzag", strokeColorHex: nil, strokeWidth: nil
        )))

        let style = try await storedStyle()
        XCTAssertEqual(style?.cap, ConnectorStyle.default.cap)  // the valid cap was NOT applied
        XCTAssertEqual(style?.routing, ConnectorStyle.default.routing)
    }

    func testExecute_invalidColor_throwsBeforeAnyWrite() async throws {
        let validatingUseCase = ValidationAsyncUseCaseDecorator(useCase!)
        await XCTAssertThrowsErrorAsync(try await validatingUseCase.execute(SetConnectorStyleRequest(
            connectorID: self.connectorID, cap: "line", routing: nil, strokeColorHex: "not-a-hex", strokeWidth: 9
        )))

        let style = try await storedStyle()
        XCTAssertEqual(style, ConnectorStyle.default)
    }

    func testExecute_outOfRangeStrokeWidth_throwsBeforeAnyWrite() async throws {
        // The bundled MCP edit path must reject an out-of-range width too, not only the single-field
        // `SetConnectorStrokeWidthRequest` — otherwise the same footgun stays open here.
        let validatingUseCase = ValidationAsyncUseCaseDecorator(useCase!)
        await XCTAssertThrowsErrorAsync(try await validatingUseCase.execute(SetConnectorStyleRequest(
            connectorID: self.connectorID, cap: "line", routing: nil, strokeColorHex: nil, strokeWidth: 1000
        )))

        let style = try await storedStyle()
        XCTAssertEqual(style, ConnectorStyle.default)
    }

    func testExecute_unknownConnectorID_throwsNotFound() async throws {
        // A stale connector id is no longer a silent no-op: the domain transform throws `notFound`
        // (ticket F59ECB92), so a mutate that applies nothing surfaces as an error rather than a
        // phantom success. The first style field applied (`cap`) is the one that resolves the id.
        let missingID = UUID()
        do {
            _ = try await useCase.execute(SetConnectorStyleRequest(
                connectorID: missingID, cap: "line", routing: nil, strokeColorHex: nil, strokeWidth: nil
            ))
            XCTFail("Expected setStyle on an unknown connector id to throw")
        } catch {
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Connector", id: missingID))
        }
        // And nothing was written.
        let style = try await storedStyle()
        XCTAssertEqual(style, ConnectorStyle.default)
    }
}

/// Async counterpart of `XCTAssertThrowsError` (which only takes an autoclosure of sync code).
private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected the call to throw", file: file, line: line)
    } catch {}
}
