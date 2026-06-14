import XCTest
@testable import KanvasCore

/// `SearchCardsUseCase` is a thin delegate: it forwards `query` to
/// `BoardManagementServiceProtocol.matchingCardIDs(query:)` and returns the result unchanged
/// (ticket 59B10FBA). These tests pin that delegation against a mock service.
final class SearchCardsUseCaseTests: XCTestCase {

    private var service: MockBoardManagementService!
    private var sut: SearchCardsUseCaseImpl!

    override func setUp() {
        super.setUp()
        service = MockBoardManagementService()
        sut = SearchCardsUseCaseImpl(boardManagement: service)
    }

    override func tearDown() {
        service = nil
        sut = nil
        super.tearDown()
    }

    func testExecute_forwardsQueryToService() async throws {
        _ = try await sut.execute(query: "milk")
        XCTAssertEqual(service.lastQuery, "milk")
    }

    func testExecute_callsServiceExactlyOnce() async throws {
        _ = try await sut.execute(query: "milk")
        XCTAssertEqual(service.matchingCallCount, 1)
    }

    func testExecute_returnsServiceResultUnchanged() async throws {
        let expected: Set<UUID> = [UUID(), UUID()]
        service.stubbedMatches = expected
        let result = try await sut.execute(query: "x")
        XCTAssertEqual(result, expected)
    }
}

/// Minimal `BoardManagementServiceProtocol` double recording the `matchingCardIDs` call and serving a
/// stubbed result. Every other protocol method is an unreachable stub (the use case only calls
/// `matchingCardIDs`). `@unchecked Sendable` is safe: mutation is on the test's serial flow.
final class MockBoardManagementService: BoardManagementServiceProtocol, @unchecked Sendable {
    private(set) var matchingCallCount = 0
    private(set) var lastQuery: String?
    var stubbedMatches: Set<UUID> = []

    func matchingCardIDs(query: String) async throws -> Set<UUID> {
        matchingCallCount += 1
        lastQuery = query
        return stubbedMatches
    }

    func matchingCardIDs(in state: BoardState, query: String) -> Set<UUID> {
        lastQuery = query
        return stubbedMatches
    }

    // MARK: Unused protocol surface

    private func unimplemented() -> Never { fatalError("not used by SearchCardsUseCase tests") }

    func loadActiveBoard() async throws -> BoardState { unimplemented() }
    func bootstrapActiveBoard() async throws -> BoardState { unimplemented() }
    func bootstrapActiveBoardWithCatalog() async throws -> ActiveBoardSnapshot { unimplemented() }
    func loadBoard(id: Board.ID) async throws -> BoardState { unimplemented() }
    func listBoards() async throws -> BoardCatalog { unimplemented() }
    func loadTemplate() async throws -> BoardTemplate { unimplemented() }
    func addBoard(title: String) async throws -> BoardState { unimplemented() }
    func registeringBoard(_ board: Board, into catalog: BoardCatalog) -> BoardCatalog { unimplemented() }
    func recoveringActiveBoard(in catalog: BoardCatalog) -> BoardCatalog { unimplemented() }
    func switchBoard(to id: Board.ID) async throws -> BoardState { unimplemented() }
    func renameBoard(id: Board.ID, title: String) async throws -> (boards: [Board], activeBoardID: UUID?) {
        unimplemented()
    }
    func deleteBoard(id: Board.ID) async throws -> BoardState { unimplemented() }
    func deletingBoard(id: Board.ID, from catalog: BoardCatalog) throws -> BoardCatalog { unimplemented() }
    func undo() async throws -> UndoOutcome { unimplemented() }
    func saveTemplate(_ template: BoardTemplate) async throws { unimplemented() }
    func editBoardSettings(boardID: Board.ID, settings: BoardSettings,
                           columns: [ColumnAppearanceUpdate]) async throws -> BoardState { unimplemented() }
    func editColumnAppearance(columnID: Column.ID,
                              edit: ColumnAppearanceFields) async throws -> BoardState { unimplemented() }
}
