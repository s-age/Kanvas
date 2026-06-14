import XCTest
@testable import KanvasCore

/// `settingFillColor` sets a sticky's per-sticky background fill, and clears it (nil) back to the
/// board's free/task default.
final class StickyServiceFillColorTests: XCTestCase {

    private var service: StickyService!

    override func setUp() {
        super.setUp()
        service = StickyService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func stateWithSticky() -> (BoardState, UUID) {
        let cardID = UUID()
        let sticky = Sticky(cardID: cardID, content: "a", position: .zero, sortIndex: 0)
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [sticky])
        state.settings.canvas = .default
        return (state, sticky.id)
    }

    func testSettingFillColor_setsTheFill() throws {
        let (state, id) = stateWithSticky()

        let result = try service.settingFillColor(id: id, fillColorHex: "FF8800", in: state)

        XCTAssertEqual(result.stickies.first?.fillColorHex, "FF8800")
    }

    func testSettingFillColor_nilClearsTheFill() throws {
        var (state, id) = stateWithSticky()
        state.stickies[0].fillColorHex = "FF8800"

        let result = try service.settingFillColor(id: id, fillColorHex: nil, in: state)

        XCTAssertNil(result.stickies.first?.fillColorHex)
    }

    func testSettingFillColor_unknownID_throwsNotFound() {
        let (state, _) = stateWithSticky()
        let missingID = UUID()

        XCTAssertThrowsError(try service.settingFillColor(id: missingID, fillColorHex: "FF8800", in: state)) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Sticky", id: missingID))
        }
    }
}
