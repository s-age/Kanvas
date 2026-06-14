import XCTest
@testable import KanvasCore

/// `BoardManagementService.editColumnAppearance` — the single-column colour / completion edit that
/// resolves the keep/clear/set overlay and the single-completion invariant **inside one `mutate`**
/// against the column reloaded under the store lock (the atomic replacement for the MCP gateway's
/// former two-flock read-modify-write; ticket 620B3601). Driven through the real `mutate` boundary
/// via `StubBoardRepository`, which echoes the held `BoardState` so the imperative verb runs once.
final class BoardManagementServiceColumnAppearanceTests: XCTestCase {

    private func makeService(_ state: BoardState) -> (BoardManagementService, StubBoardRepository) {
        let repository = StubBoardRepository(state: state)
        let service = BoardManagementService(
            repository: repository,
            columnService: ColumnService(repository: StubBoardRepository()),
            diagnostics: SpyDiagnosticsLogger()
        )
        return (service, repository)
    }

    private func column(
        _ id: UUID = UUID(), headerColorHex: String? = nil, bodyColorHex: String? = nil,
        indicatorColorHex: String? = nil, isCompletion: Bool = false
    ) -> Column {
        Column(id: id, boardID: UUID(), title: "Col", sortIndex: 0,
               isCompletionColumn: isCompletion, headerColorHex: headerColorHex,
               bodyColorHex: bodyColorHex, indicatorColorHex: indicatorColorHex)
    }

    private func board(_ columns: [Column]) -> BoardState {
        BoardState(board: Board(title: "B"), columns: columns, cards: [], stickies: [])
    }

    // MARK: - keep / clear / set per field

    func testEditColumnAppearance_setsTargetColourField() async throws {
        let target = column(headerColorHex: "#000000")
        let (service, _) = makeService(board([target]))

        let state = try await service.editColumnAppearance(
            columnID: target.id,
            edit: ColumnAppearanceFields(headerColorHex: .some("#FF0000"))
        )

        XCTAssertEqual(state.columns.first { $0.id == target.id }?.headerColorHex, "#FF0000")
    }

    func testEditColumnAppearance_omittedField_keepsCurrentValue() async throws {
        let target = column(headerColorHex: "#000000", bodyColorHex: "#222222")
        let (service, _) = makeService(board([target]))

        // Only the indicator is set; header/body omitted → kept.
        let state = try await service.editColumnAppearance(
            columnID: target.id,
            edit: ColumnAppearanceFields(indicatorColorHex: .some("#00FF00"))
        )

        let edited = try XCTUnwrap(state.columns.first { $0.id == target.id })
        XCTAssertEqual(edited.headerColorHex, "#000000")
        XCTAssertEqual(edited.bodyColorHex, "#222222")
        XCTAssertEqual(edited.indicatorColorHex, "#00FF00")
    }

    func testEditColumnAppearance_clearSentinel_clearsTargetField() async throws {
        let target = column(headerColorHex: "#000000")
        let (service, _) = makeService(board([target]))

        let state = try await service.editColumnAppearance(
            columnID: target.id,
            edit: ColumnAppearanceFields(headerColorHex: .some(nil))  // clear
        )

        XCTAssertNil(state.columns.first { $0.id == target.id }?.headerColorHex)
    }

    func testEditColumnAppearance_preservesSiblingColumnVerbatim() async throws {
        let target = column(headerColorHex: "#000000")
        let sibling = column(headerColorHex: "#ABCDEF", bodyColorHex: "#FEDCBA", isCompletion: true)
        let (service, _) = makeService(board([target, sibling]))

        let state = try await service.editColumnAppearance(
            columnID: target.id,
            edit: ColumnAppearanceFields(headerColorHex: .some("#FF0000"))
        )

        let preserved = try XCTUnwrap(state.columns.first { $0.id == sibling.id })
        XCTAssertEqual(preserved.headerColorHex, "#ABCDEF")
        XCTAssertEqual(preserved.bodyColorHex, "#FEDCBA")
        XCTAssertTrue(preserved.isCompletionColumn)
    }

    // MARK: - atomicity

    func testEditColumnAppearance_opensThePersistenceBoundaryExactlyOnce() async throws {
        // The whole edit is one `mutate` — one flock + read-modify-write + undo entry — not the
        // load-then-write across two flocks the gateway previously did (ticket 620B3601).
        let target = column()
        let (service, repository) = makeService(board([target]))

        _ = try await service.editColumnAppearance(
            columnID: target.id, edit: ColumnAppearanceFields(headerColorHex: .some("#FF0000"))
        )

        XCTAssertEqual(repository.mutateCallCount, 1)
    }

    // MARK: - completion-column switch (single-completion invariant)

    func testEditColumnAppearance_promotingNewCompletion_clearsSiblingFlag() async throws {
        let oldCompletion = column(isCompletion: true)
        let target = column(isCompletion: false)
        let (service, _) = makeService(board([oldCompletion, target]))

        let state = try await service.editColumnAppearance(
            columnID: target.id, edit: ColumnAppearanceFields(isCompletionColumn: true)
        )

        XCTAssertFalse(state.columns.first { $0.id == oldCompletion.id }?.isCompletionColumn ?? true)
    }

    func testEditColumnAppearance_promotingNewCompletion_flagsTarget() async throws {
        let oldCompletion = column(isCompletion: true)
        let target = column(isCompletion: false)
        let (service, _) = makeService(board([oldCompletion, target]))

        let state = try await service.editColumnAppearance(
            columnID: target.id, edit: ColumnAppearanceFields(isCompletionColumn: true)
        )

        XCTAssertTrue(state.columns.first { $0.id == target.id }?.isCompletionColumn ?? false)
    }

    func testEditColumnAppearance_promotingNewCompletion_yieldsExactlyOneFlag() async throws {
        let oldCompletion = column(isCompletion: true)
        let target = column(isCompletion: false)
        let (service, _) = makeService(board([oldCompletion, target]))

        let state = try await service.editColumnAppearance(
            columnID: target.id, edit: ColumnAppearanceFields(isCompletionColumn: true)
        )

        XCTAssertEqual(state.columns.filter(\.isCompletionColumn).count, 1)
    }

    func testEditColumnAppearance_colourOnly_leavesExistingCompletionUntouched() async throws {
        let completion = column(isCompletion: true)
        let target = column(headerColorHex: "#000000", isCompletion: false)
        let (service, _) = makeService(board([completion, target]))

        let state = try await service.editColumnAppearance(
            columnID: target.id, edit: ColumnAppearanceFields(headerColorHex: .some("#FF0000"))
        )

        XCTAssertTrue(state.columns.first { $0.id == completion.id }?.isCompletionColumn ?? false)
    }

    func testEditColumnAppearance_clearingTargetCompletion_doesNotDemoteSiblings() async throws {
        let sibling = column(isCompletion: true)
        let target = column(isCompletion: true)
        let (service, _) = makeService(board([sibling, target]))

        let state = try await service.editColumnAppearance(
            columnID: target.id, edit: ColumnAppearanceFields(isCompletionColumn: false)
        )

        XCTAssertTrue(state.columns.first { $0.id == sibling.id }?.isCompletionColumn ?? false)
        XCTAssertFalse(state.columns.first { $0.id == target.id }?.isCompletionColumn ?? true)
    }

    // MARK: - unknown column

    func testEditColumnAppearance_unknownColumn_throwsNotFound() async throws {
        let (service, _) = makeService(board([column()]))

        do {
            _ = try await service.editColumnAppearance(
                columnID: UUID(), edit: ColumnAppearanceFields()
            )
            XCTFail("Expected notFound")
        } catch let OperationError.notFound(entityKind, _) {
            XCTAssertEqual(entityKind, "Column")
        }
    }
}
