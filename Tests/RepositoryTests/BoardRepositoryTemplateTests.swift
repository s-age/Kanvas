import XCTest
@testable import KanvasCore

/// `BoardRepository`'s Default-template persistence and by-id board mutation: the template falls
/// back to the built-in default when none is stored, round-trips through the store, and editing a
/// non-active board persists it without disturbing the active board's cached state / undo history.
final class BoardRepositoryTemplateTests: XCTestCase {

    private var store: InMemoryBoardStore!
    private var repository: BoardRepository!

    override func setUp() {
        super.setUp()
        store = InMemoryBoardStore(initial: BoardSnapshotMapper.toDTO(BoardState.empty(title: "active")))
        repository = BoardRepository(store: store, diagnostics: SpyDiagnosticsLogger())
    }

    override func tearDown() {
        repository = nil
        store = nil
        super.tearDown()
    }

    // MARK: - template

    func testLoadTemplate_whenNonePersisted_returnsDefault() async throws {
        let template = try await repository.loadTemplate()

        XCTAssertEqual(template.columns.map(\.title), BoardTemplate.default.columns.map(\.title))
    }

    func testSaveTemplate_roundTripsThroughStore() async throws {
        var settings = BoardSettings.default
        settings.global.textColorHex = "FEFEFE"
        let saved = BoardTemplate(
            settings: settings,
            columns: [TemplateColumn(title: "Only", sortIndex: 0, headerColorHex: "123456")]
        )

        try await repository.saveTemplate(saved)
        let loaded = try await repository.loadTemplate()

        XCTAssertEqual(loaded.settings.global.textColorHex, "FEFEFE")
        XCTAssertEqual(loaded.columns.map(\.title), ["Only"])
        XCTAssertEqual(loaded.columns.first?.headerColorHex, "123456")
    }

    func testSaveTemplate_roundTripsIndicatorColour() async throws {
        let saved = BoardTemplate(
            settings: .default,
            columns: [TemplateColumn(title: "Only", sortIndex: 0, indicatorColorHex: "FF9500")]
        )

        try await repository.saveTemplate(saved)
        let loaded = try await repository.loadTemplate()

        XCTAssertEqual(loaded.columns.first?.indicatorColorHex, "FF9500")
    }

    // MARK: - mutateBoard

    func testMutateBoard_nonActiveBoard_persistsWithoutSwitchingActive() async throws {
        let firstID = try await repository.loadActiveBoard().board.id   // currently active
        let other = BoardState.empty(title: "other")
        _ = try await repository.insertBoard(other)             // `other` is now active; firstID non-active

        // Title is catalog-authoritative (reconciled on load), so assert a snapshot-stored field.
        _ = try await repository.mutateBoard(id: firstID) { state in
            var next = state
            next.settings.global.backgroundColorHex = "ABCDEF"
            return next
        }

        let activeID = try await repository.loadActiveBoard().board.id
        XCTAssertEqual(activeID, other.board.id)             // active unchanged
        let loadedHex = try await repository.loadBoard(id: firstID).settings.global.backgroundColorHex
        XCTAssertEqual(loadedHex, "ABCDEF")
    }

    func testMutateBoard_nonActiveBoard_doesNotRecordUndoOnActive() async throws {
        let firstID = try await repository.loadActiveBoard().board.id
        let other = BoardState.empty(title: "other")
        _ = try await repository.insertBoard(other)             // resets undo; `other` active

        _ = try await repository.mutateBoard(id: firstID) { state in
            var next = state
            next.board.title = "x"
            return next
        }

        let undone = try await repository.undo()
        XCTAssertEqual(undone, .nothingToUndo)  // active board accrued no undo entry
    }
}
