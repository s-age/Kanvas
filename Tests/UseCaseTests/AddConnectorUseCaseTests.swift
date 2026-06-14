import XCTest
@testable import KanvasCore

/// `AddConnectorUseCaseImpl` over the real repository + services. Pins its two branches: linking an
/// existing sticky, and the more complex "drop on empty → create a new sticky **and** the connector
/// in one transaction" path.
final class AddConnectorUseCaseTests: XCTestCase {

    private let cardID = UUID()
    private var store: InMemoryBoardStore!
    private var repository: BoardRepository!
    private var useCase: AddConnectorUseCaseImpl!

    private func makeSticky(_ id: UUID) -> Sticky {
        Sticky(id: id, cardID: cardID, content: "s", position: .zero, sortIndex: 0)
    }

    private func seed(stickies: [Sticky]) {
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: stickies)
        state.stickies = stickies
        store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(state))
        repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
        let connectorService = ConnectorService(
            repository: repository, stickyService: StickyService(repository: repository)
        )
        useCase = AddConnectorUseCaseImpl(connectorService: connectorService)
    }

    // MARK: - existing target

    func testExecute_existingTarget_addsConnectorWithoutNewSticky() async throws {
        let source = makeSticky(UUID())
        let target = makeSticky(UUID())
        seed(stickies: [source, target])

        _ = try await useCase.execute(AddConnectorRequest(
            cardID: cardID,
            sourceStickyID: source.id, sourceEdge: "right", targetEdge: "left",
            existingTargetStickyID: target.id,
            newStickyX: 0, newStickyY: 0, newStickyWidth: 200, newStickyHeight: 150
        ))

        let state = try await repository.loadActiveBoard()
        XCTAssertEqual(state.stickies.count, 2)  // no new sticky
        XCTAssertEqual(state.connectors.count, 1)
        let connector = state.connectors.first
        XCTAssertEqual(connector?.sourceStickyID, source.id)
        XCTAssertEqual(connector?.targetStickyID, target.id)
        XCTAssertEqual(connector?.sourceEdge, .right)
        XCTAssertEqual(connector?.targetEdge, .left)
    }

    // MARK: - drop on empty → new sticky + connector (one transaction)

    func testExecute_emptyDrop_createsNewStickyAndConnector() async throws {
        let source = makeSticky(UUID())
        seed(stickies: [source])

        _ = try await useCase.execute(AddConnectorRequest(
            cardID: cardID,
            sourceStickyID: source.id, sourceEdge: "bottom", targetEdge: "top",
            existingTargetStickyID: nil,
            newStickyX: 300, newStickyY: 400, newStickyWidth: 200, newStickyHeight: 150
        ))

        let state = try await repository.loadActiveBoard()
        XCTAssertEqual(state.stickies.count, 2)  // the grown sticky was added
        XCTAssertEqual(state.connectors.count, 1)

        let newSticky = state.stickies.first { $0.id != source.id }
        XCTAssertEqual(newSticky?.position.x, 300)
        XCTAssertEqual(newSticky?.position.y, 400)
        // The connector targets the brand-new sticky — both committed in one mutation.
        XCTAssertEqual(state.connectors.first?.sourceStickyID, source.id)
        XCTAssertEqual(state.connectors.first?.targetStickyID, newSticky?.id)
    }

    // MARK: - explicit stroke colour at creation

    func testExecute_specifiedStrokeColor_isHonouredVerbatim() async throws {
        let source = makeSticky(UUID())
        let target = makeSticky(UUID())
        seed(stickies: [source, target])

        _ = try await useCase.execute(AddConnectorRequest(
            cardID: cardID,
            sourceStickyID: source.id, sourceEdge: "right", targetEdge: "left",
            existingTargetStickyID: target.id,
            newStickyX: 0, newStickyY: 0, newStickyWidth: 200, newStickyHeight: 150,
            strokeColorHex: "FF8800"
        ))

        let state = try await repository.loadActiveBoard()
        XCTAssertEqual(state.connectors.first?.style.strokeColorHex, "FF8800")
    }

    func testExecute_invalidEdge_throwsAndAddsNothing() async {
        let source = makeSticky(UUID())
        seed(stickies: [source])
        let validatingUseCase = ValidationAsyncUseCaseDecorator(useCase!)

        await XCTAssertThrowsErrorAsync(try await validatingUseCase.execute(AddConnectorRequest(
            cardID: self.cardID,
            sourceStickyID: source.id, sourceEdge: "diagonal", targetEdge: "left",
            existingTargetStickyID: nil,
            newStickyX: 0, newStickyY: 0, newStickyWidth: 200, newStickyHeight: 150
        )))

        let state = try? await repository.loadActiveBoard()
        XCTAssertEqual(state?.connectors.count, 0)
        XCTAssertEqual(state?.stickies.count, 1)
    }
}

// MARK: - Test helpers
//
// The in-memory `BoardStoreProtocol` lives in `Tests/Support/InMemoryBoardStore.swift`.

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        // expected
    }
}
