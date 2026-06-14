import XCTest
@testable import KanvasCore

/// `KanvasMCPGateway.echoDetail` (ticket 1DCBF9C9): a canvas write echoes the card detail the
/// mutation already returned — **but only when it is for the requested card** (`id == cardID`).
/// When the returned detail is for a different card (an inconsistent `cardID` argument), the
/// gateway must fall back to a scoped reload of the requested card rather than echo the wrong one.
/// Driven through the public `editSticky` path.
final class KanvasMCPCanvasEchoTests: XCTestCase {

    private let cardID = UUID()

    func testEditSticky_echoesReturnedDetail_whenItMatchesTheCard() async throws {
        let mockEdit = ConfigurableEditSticky()
        let spyLoad = SpyLoadCardDetail()
        mockEdit.response = boardMutation(detail: cardDetailFixture(id: cardID, markdown: "FROM_MUTATION"))
        let sut = makeGateway(editSticky: mockEdit, loadCardDetail: spyLoad)

        let json = try await sut.editSticky(cardID: cardID.uuidString, stickyID: UUID().uuidString, content: "x")

        XCTAssertTrue(json.contains("FROM_MUTATION"))
        XCTAssertEqual(spyLoad.callCount, 0)  // adopted from the mutation — no reload
    }

    func testEditSticky_reloadsCard_whenReturnedDetailIsForADifferentCard() async throws {
        let mockEdit = ConfigurableEditSticky()
        let spyLoad = SpyLoadCardDetail()
        // Mutation carries a detail for some OTHER card → must not be echoed for `cardID`.
        mockEdit.response = boardMutation(detail: cardDetailFixture(id: UUID(), markdown: "WRONG_CARD"))
        let sut = makeGateway(editSticky: mockEdit, loadCardDetail: spyLoad)

        let json = try await sut.editSticky(cardID: cardID.uuidString, stickyID: UUID().uuidString, content: "x")

        XCTAssertEqual(spyLoad.callCount, 1)        // fell back to a scoped reload
        XCTAssertTrue(json.contains("RELOADED"))    // echoed the requested card, not the wrong one
        XCTAssertFalse(json.contains("WRONG_CARD"))
    }
}

// MARK: - reconnectConnector

extension KanvasMCPCanvasEchoTests {

    func testReconnectConnector_bothSidesNil_rejectsBeforeAnyWrite() async throws {
        let reconnect = ConfigurableReconnect()
        let sut = makeGateway(loadCardDetail: SpyLoadCardDetail(), reconnectConnector: reconnect)
        do {
            _ = try await sut.reconnectConnector(
                cardID: cardID.uuidString, connectorID: UUID().uuidString, source: nil, target: nil
            )
            XCTFail("Expected emptyConnectorEdit")
        } catch let error as KanvasMCPError {
            XCTAssertEqual("\(error)", "\(KanvasMCPError.emptyConnectorEdit)")
        }
        XCTAssertEqual(reconnect.callCount, 0)  // never reached the use case
    }

    func testReconnectConnector_unknownConnector_throwsNotFoundBeforeWrite() async throws {
        let reconnect = ConfigurableReconnect()
        // The load-detail carries NO connectors, so the card-scoped pre-check fails.
        let sut = makeGateway(loadCardDetail: SpyLoadCardDetail(), reconnectConnector: reconnect)
        do {
            _ = try await sut.reconnectConnector(
                cardID: cardID.uuidString, connectorID: UUID().uuidString,
                source: ConnectorEndpointArg(stickyID: UUID().uuidString, edge: "top"), target: nil
            )
            XCTFail("Expected notFound")
        } catch let error as KanvasMCPError {
            if case .notFound(let kind, _) = error { XCTAssertEqual(kind, "Connector") } else {
                XCTFail("Expected notFound(Connector), got \(error)")
            }
        }
        XCTAssertEqual(reconnect.callCount, 0)
    }

    func testReconnectConnector_validSource_invokesUseCaseAndEchoesCanvas() async throws {
        let connectorID = UUID()
        let reconnect = ConfigurableReconnect()
        reconnect.response = boardMutation(
            detail: cardDetailFixture(id: cardID, markdown: "RECONNECTED", connectorID: connectorID)
        )
        let load = SpyLoadCardDetail(connectorID: connectorID)
        let sut = makeGateway(loadCardDetail: load, reconnectConnector: reconnect)

        let json = try await sut.reconnectConnector(
            cardID: cardID.uuidString, connectorID: connectorID.uuidString,
            source: ConnectorEndpointArg(stickyID: UUID().uuidString, edge: "left"), target: nil
        )

        XCTAssertEqual(reconnect.callCount, 1)
        XCTAssertTrue(json.contains("RECONNECTED"))
    }
}

private final class ConfigurableReconnect: AsyncUseCase, @unchecked Sendable {
    private(set) var callCount = 0
    var response: BoardMutationResponse?
    func execute(_ request: ReconnectConnectorRequest) async throws -> BoardMutationResponse {
        callCount += 1
        return response ?? boardMutation(detail: nil)
    }
}

// MARK: - Configurable edit-sticky + spy load-card-detail

private final class ConfigurableEditSticky: AsyncUseCase, @unchecked Sendable {
    var response: BoardMutationResponse?
    func execute(_ request: EditStickyRequest) async throws -> BoardMutationResponse {
        response ?? boardMutation(detail: nil)
    }
}

private final class SpyLoadCardDetail: LoadCardDetailUseCase, @unchecked Sendable {
    private(set) var callCount = 0
    private let connectorID: UUID?
    init(connectorID: UUID? = nil) { self.connectorID = connectorID }
    func execute(cardID: UUID) async throws -> CardDetailResponse? {
        callCount += 1
        return cardDetailFixture(id: cardID, markdown: "RELOADED", connectorID: connectorID)
    }
}

// MARK: - Fixtures

private func boardResponseFixture(id: UUID = UUID()) -> BoardResponse {
    BoardResponse(
        board: BoardSummary(id: id, title: ""),
        columns: [], labels: [], settings: SettingsTestFixtures.defaultSettings
    )
}

private func boardMutation(detail: CardDetailResponse?) -> BoardMutationResponse {
    BoardMutationResponse(board: boardResponseFixture(), cardDetail: detail)
}

private func cardDetailFixture(id: UUID, markdown: String, connectorID: UUID? = nil) -> CardDetailResponse {
    let connectors = connectorID.map { [connectorFixture(id: $0)] } ?? []
    return CardDetailResponse(
        id: id, title: "Card", markdownContent: markdown,
        status: .todo, columnTitle: "To Do",
        schedule: nil, labels: [], assignee: nil, prURL: nil, completedAt: nil,
        stickies: [], shapes: [], images: [], texts: [], connectors: connectors
    )
}

private func connectorFixture(id: UUID) -> ConnectorResponse {
    ConnectorResponse(
        id: id, sourceStickyID: UUID(), sourceEdge: .right,
        targetStickyID: UUID(), targetEdge: .left,
        cap: .arrow, routing: .straight, strokeColorHex: nil,
        strokeWidth: 2, minStrokeWidth: 1, maxStrokeWidth: 40,
        waypointOffsetX: nil, waypointOffsetY: nil
    )
}

// MARK: - Gateway factory

private func makeGateway(
    editSticky: EditStickyUseCase = MutStub<EditStickyRequest>(),
    loadCardDetail: any LoadCardDetailUseCase,
    reconnectConnector: ReconnectConnectorUseCase = MutStub<ReconnectConnectorRequest>()
) -> KanvasMCPGateway {
    KanvasMCPGateway(
        loadActiveBoard: BoardStub<LoadActiveBoardRequest>(),
        loadBoardByID: BoardStub<LoadBoardByIDRequest>(),
        listBoards: ListBoardsStub(),
        addCard: AddCardStub(),
        editCard: MutStub<EditCardRequest>(),
        moveCard: MutStub<MoveCardRequest>(),
        deleteCard: BoardStub<DeleteCardRequest>(),
        addColumn: BoardStub<AddColumnRequest>(),
        renameColumn: BoardStub<RenameColumnRequest>(),
        deleteColumn: BoardStub<DeleteColumnRequest>(),
        editBoardSettings: BoardStub<EditBoardSettingsRequest>(),
        editColumnAppearance: BoardStub<EditColumnAppearanceRequest>(),
        loadCardDetail: loadCardDetail,
        addSticky: MutStub<AddStickyRequest>(),
        editSticky: editSticky,
        moveSticky: MutStub<MoveStickyRequest>(),
        setStickyFrame: MutStub<SetStickyFrameRequest>(),
        deleteSticky: MutStub<DeleteStickyRequest>(),
        promoteSticky: MutStub<PromoteStickyRequest>(),
        demoteSticky: MutStub<DemoteStickyRequest>(),
        addText: MutStub<AddTextRequest>(),
        editText: MutStub<EditTextRequest>(),
        moveText: MutStub<MoveTextRequest>(),
        resizeText: MutStub<ResizeTextRequest>(),
        setTextColor: MutStub<SetTextColorRequest>(),
        setTextFontSize: MutStub<SetTextFontSizeRequest>(),
        deleteText: MutStub<DeleteTextRequest>(),
        addConnector: MutStub<AddConnectorRequest>(),
        deleteConnector: MutStub<DeleteConnectorRequest>(),
        setConnectorStyle: MutStub<SetConnectorStyleRequest>(),
        reconnectConnector: reconnectConnector,
        saveImageAsset: SaveImageAssetStub(),
        deleteMarkdownImage: MutStub<DeleteMarkdownImageRequest>()
    )
}

private struct SaveImageAssetStub: AsyncUseCase, Sendable {
    func execute(_ request: SaveImageAssetRequest) async throws -> SaveImageAssetResponse {
        SaveImageAssetResponse(assetID: UUID())
    }
}

private struct MutStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardMutationResponse { boardMutation(detail: nil) }
}

private struct BoardStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardResponse { boardResponseFixture() }
}

private struct ListBoardsStub: AsyncUseCase, Sendable {
    func execute(_ request: ListBoardsRequest) async throws -> BoardListResponse {
        BoardListResponse(boards: [], activeBoardID: nil)
    }
}

private struct AddCardStub: AsyncUseCase, Sendable {
    func execute(_ request: AddCardRequest) async throws -> AddCardResponse {
        AddCardResponse(newCardID: UUID(), board: boardResponseFixture())
    }
}
