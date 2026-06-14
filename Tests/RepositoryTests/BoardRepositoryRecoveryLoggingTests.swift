import XCTest
@testable import KanvasCore

/// `BoardRepository` must **log** every transport recovery the snapshot decoder applies on load — in
/// this whole-blob store the recovery is a latent write (the next save persists the coerced/dropped
/// value), so it must be observable via the injected diagnostics port, not silent
/// (`arch-repository.md` → "Latent write-back in a whole-blob model"). A clean snapshot logs nothing.
final class BoardRepositoryRecoveryLoggingTests: XCTestCase {

    private var diagnostics: SpyDiagnosticsLogger!

    override func setUp() {
        super.setUp()
        diagnostics = SpyDiagnosticsLogger()
    }

    override func tearDown() {
        diagnostics = nil
        super.tearDown()
    }

    func testLoadActiveBoard_snapshotWithDanglingConnector_logsRecoveryAtError() async throws {
        let repository = repository(seeding: snapshotWithDanglingConnector())

        _ = try await repository.loadActiveBoard()

        XCTAssertEqual(diagnostics.messages(at: .error),
                       ["board snapshot recovery: connector dropped: endpoint sticky absent"])
    }

    func testLoadActiveBoard_recoveryLog_carriesBoardIDInPrivateDetail() async throws {
        let dto = snapshotWithDanglingConnector()
        let repository = repository(seeding: dto)

        _ = try await repository.loadActiveBoard()

        XCTAssertEqual(diagnostics.privateDetails(at: .error).first?.hasPrefix("board=\(dto.board.id) "), true)
    }

    func testLoadActiveBoard_cleanSnapshot_logsNothing() async throws {
        let clean = BoardSnapshotMapper.toDTO(BoardState.withDefaultColumns(title: "Clean"))
        let repository = repository(seeding: clean)

        _ = try await repository.loadActiveBoard()

        XCTAssertTrue(diagnostics.messages.isEmpty)
    }

    /// `exclusive` re-decodes the active board on every operation; without dedup an unhealed board
    /// would re-log the same recovery on each read. It must be logged once per process.
    func testLoadActiveBoard_repeatedReads_logRecoveryOnlyOnce() async throws {
        let repository = repository(seeding: snapshotWithDanglingConnector())

        _ = try await repository.loadActiveBoard()
        _ = try await repository.loadActiveBoard()
        _ = try await repository.loadActiveBoard()

        XCTAssertEqual(diagnostics.messages(at: .error).count, 1)
    }

    func testRecoverOrphanedBoards_snapshotWithRecovery_logsRecovery() async throws {
        let store = InMemoryBoardStore()
        let dto = snapshotWithDanglingConnector()
        try store.save(boardID: dto.board.id, dto)  // snapshot on disk, no catalog → recovery rebuild
        let repository = BoardRepository(store: store, diagnostics: diagnostics)

        _ = try await repository.recoverOrphanedBoards()

        XCTAssertEqual(diagnostics.messages(at: .error),
                       ["board snapshot recovery: connector dropped: endpoint sticky absent"])
    }

    func testMigrateLegacyBoard_legacySnapshotWithRecovery_logsRecovery() async throws {
        let store = InMemoryBoardStore()
        store.legacy = snapshotWithDanglingConnector()
        let repository = BoardRepository(store: store, diagnostics: diagnostics)

        _ = try await repository.migrateLegacyBoard()

        XCTAssertEqual(diagnostics.messages(at: .error),
                       ["board snapshot recovery: connector dropped: endpoint sticky absent"])
    }

    // MARK: - Fixtures

    private func repository(seeding dto: BoardSnapshotDTO) -> BoardRepository {
        BoardRepository(store: InMemoryBoardStore(initial: dto), diagnostics: diagnostics)
    }

    /// A snapshot with one present sticky and a connector whose target sticky is absent — the decoder
    /// drops the connector on load and records a recovery.
    private func snapshotWithDanglingConnector() -> BoardSnapshotDTO {
        let cardID = UUID()
        let present = UUID()
        return BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"),
            columns: [], cards: [],
            stickies: [StickyDTO(id: present, cardID: cardID, linkedCardID: nil, content: "x",
                                 positionX: 0, positionY: 0, width: 100, height: 80,
                                 textColorHex: nil, fontSize: nil, fillColorHex: nil,
                                 sortIndex: nil, labelIDs: nil)],
            shapes: nil, images: nil,
            connectors: [ConnectorDTO(id: UUID(), cardID: cardID,
                                      sourceStickyID: present, sourceEdge: "right",
                                      targetStickyID: UUID(), targetEdge: "left",
                                      cap: nil, routing: nil, strokeColorHex: nil, strokeWidth: nil)],
            labels: nil
        )
    }
}
