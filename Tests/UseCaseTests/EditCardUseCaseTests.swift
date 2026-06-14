import XCTest
@testable import KanvasCore

/// `EditCardUseCaseImpl.execute` normalizes the `prURL` request field before handing it to
/// `CardService.edit`, with the same double-optional semantics as `assignee`:
/// `nil` → leave unchanged, blank → clear (`.some(nil)`), non-blank → set trimmed (`.some(.some(v))`).
/// This is the contract the dedicated `board_card_set_pr_url` MCP tool relies on (empty string clears).
final class EditCardUseCaseTests: XCTestCase {

    private var mockCardService: MockCardServiceForEditCard!
    private var sut: EditCardUseCaseImpl!

    override func setUp() {
        super.setUp()
        mockCardService = MockCardServiceForEditCard()
        sut = EditCardUseCaseImpl(cardService: mockCardService)
    }

    override func tearDown() {
        sut = nil
        mockCardService = nil
        super.tearDown()
    }

    // MARK: - prURL normalization

    func testExecute_omittedPRURL_leavesFieldUnchanged() async throws {
        _ = try await sut.execute(EditCardRequest(cardID: UUID()))

        // `nil` (no double-optional wrapping) => "leave unchanged".
        XCTAssertNil(mockCardService.lastFields?.prURL)
    }

    func testExecute_blankPRURL_normalizesToClear() async throws {
        _ = try await sut.execute(EditCardRequest(cardID: UUID(), prURL: .some("   ")))

        // `.some(nil)` => "clear" — the empty-string-clears contract of board_card_set_pr_url.
        XCTAssertEqual(mockCardService.lastFields?.prURL, .some(.none))
    }

    func testExecute_nonBlankPRURL_setsTrimmedValue() async throws {
        _ = try await sut.execute(
            EditCardRequest(cardID: UUID(), prURL: .some("  https://github.com/o/r/pull/1  "))
        )

        XCTAssertEqual(mockCardService.lastFields?.prURL, .some(.some("https://github.com/o/r/pull/1")))
    }

    // MARK: - schedule ScheduleInput → CardSchedule mapping
    //
    // Pins the Request→Domain crossing this layer owns (`request.schedule.map { $0?.toDomain }`):
    // the keep/clear/set double-optional is preserved and each `ScheduleInput` arm maps to the
    // structurally matching `CardSchedule` arm. With three shape-identical enums across three
    // layers, this is the one place the `ScheduleInput`→`CardSchedule` equivalence is pinned —
    // a forgotten/mis-wired arm (e.g. a future `milestone` case) fails here.

    func testExecute_omittedSchedule_leavesFieldUnchanged() async throws {
        _ = try await sut.execute(EditCardRequest(cardID: UUID()))

        // `nil` (no double-optional wrapping) => "leave unchanged".
        XCTAssertNil(mockCardService.lastFields?.schedule)
    }

    func testExecute_clearedSchedule_mapsToClear() async throws {
        _ = try await sut.execute(EditCardRequest(cardID: UUID(), schedule: .some(nil)))

        // `.some(nil)` => "clear" — the inner closure runs on nil, `nil?.toDomain` stays nil.
        XCTAssertEqual(mockCardService.lastFields?.schedule, .some(.none))
    }

    func testExecute_deadlineSchedule_mapsToDomainDeadline() async throws {
        let due = Date(timeIntervalSinceReferenceDate: 0)
        _ = try await sut.execute(EditCardRequest(cardID: UUID(), schedule: .some(.deadline(due))))

        XCTAssertEqual(mockCardService.lastFields?.schedule, .some(.some(.deadline(due))))
    }

    func testExecute_periodSchedule_mapsToDomainPeriod() async throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = Date(timeIntervalSinceReferenceDate: 86_400)
        _ = try await sut.execute(
            EditCardRequest(cardID: UUID(), schedule: .some(.period(start: start, end: end)))
        )

        XCTAssertEqual(mockCardService.lastFields?.schedule, .some(.some(.period(start: start, end: end))))
    }
}

// MARK: - Test doubles

private final class MockCardServiceForEditCard: CardServiceProtocol, @unchecked Sendable {
    private(set) var lastFields: EditCardFields?
    private let emptyState = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])

    // Imperative verbs — the use case calls `edit`.
    func add(_ seed: CardSeed, columnID: Column.ID) throws -> BoardState { emptyState }
    func edit(id: Card.ID, fields: EditCardFields) throws -> BoardState {
        lastFields = fields
        return emptyState
    }
    func move(id: Card.ID, toColumn: Column.ID, before: Card.ID?) throws -> BoardState { emptyState }
    func delete(id: Card.ID) throws -> BoardState { emptyState }

    // Pure transforms — unused by this test.
    func adding(_ seed: CardSeed, columnID: Column.ID, to state: BoardState) -> BoardState { state }
    func editing(id: Card.ID, fields: EditCardFields, in state: BoardState) -> BoardState { state }
    func moving(id: Card.ID, toColumn: Column.ID, before: Card.ID?, in state: BoardState) -> BoardState { state }
    func deleting(id: Card.ID, from state: BoardState) -> BoardState { state }
}
