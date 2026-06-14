import XCTest
@testable import KanvasCore

/// A new sticky must inherit the board's canvas text defaults (`CanvasSettings.defaultFontSize` /
/// `defaultTextColorHex`). These pin that the `adding` transform reads the defaults off the state's
/// settings rather than hard-coding `StickyTextStyle.default`, so a Settings → Canvas change takes
/// effect on the next-created sticky.
final class StickyServiceAddingTests: XCTestCase {

    private var service: StickyService!

    override func setUp() {
        super.setUp()
        service = StickyService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func placement() -> StickyPlacement {
        StickyPlacement(position: .zero, size: .default)
    }

    private func state(canvas: CanvasSettings) -> BoardState {
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.settings.canvas = canvas
        return state
    }

    func testAdding_appliesConfiguredFontSize() {
        let canvas = CanvasSettings(defaultFontSize: 22)

        let result = service.adding(content: "a", placement: placement(),
                                    toCardCanvas: UUID(), in: state(canvas: canvas))

        XCTAssertEqual(result.stickies.first?.style.fontSize, 22)
    }

    func testAdding_appliesConfiguredTextColor() {
        let canvas = CanvasSettings(defaultTextColorHex: "FF0000")

        let result = service.adding(content: "a", placement: placement(),
                                    toCardCanvas: UUID(), in: state(canvas: canvas))

        XCTAssertEqual(result.stickies.first?.style.colorHex, "FF0000")
    }

    func testAdding_defaultSettings_usesStyleDefaults() {
        let result = service.adding(content: "a", placement: placement(),
                                    toCardCanvas: UUID(), in: state(canvas: .default))

        XCTAssertEqual(result.stickies.first?.style, .default)
    }

    func testAdding_appliesPlacementFillColor() {
        let placement = StickyPlacement(position: .zero, size: .default, fillColorHex: "FFCC00")

        let result = service.adding(content: "a", placement: placement,
                                    toCardCanvas: UUID(), in: state(canvas: .default))

        XCTAssertEqual(result.stickies.first?.fillColorHex, "FFCC00")
    }

    func testAdding_nilPlacementFillColor_leavesStickyFillColorNil() {
        let result = service.adding(content: "a", placement: placement(),
                                    toCardCanvas: UUID(), in: state(canvas: .default))

        XCTAssertNil(result.stickies.first?.fillColorHex)
    }

    func testAdding_darkFill_autoContrastsTextToOnDarkColor() {
        let placement = StickyPlacement(position: .zero, size: .default, fillColorHex: "333333")

        let result = service.adding(content: "a", placement: placement,
                                    toCardCanvas: UUID(), in: state(canvas: .default))

        XCTAssertEqual(result.stickies.first?.style.colorHex, ContrastColor.onDarkHex)
    }

    func testAdding_lightFill_autoContrastsTextToDefaultColor() {
        let placement = StickyPlacement(position: .zero, size: .default, fillColorHex: "FFFFFF")

        let result = service.adding(content: "a", placement: placement,
                                    toCardCanvas: UUID(), in: state(canvas: .default))

        XCTAssertEqual(result.stickies.first?.style.colorHex, ContrastColor.onLightHex)
    }

    func testAdding_fillColor_overridesConfiguredDefaultTextColor() {
        // With an explicit fill, the auto-contrast colour wins over the board's default text colour
        // (which only applies to fill-less stickies).
        let canvas = CanvasSettings(defaultTextColorHex: "FF0000")
        let placement = StickyPlacement(position: .zero, size: .default, fillColorHex: "111111")

        let result = service.adding(content: "a", placement: placement,
                                    toCardCanvas: UUID(), in: state(canvas: canvas))

        XCTAssertEqual(result.stickies.first?.style.colorHex, ContrastColor.onDarkHex)
    }
}
