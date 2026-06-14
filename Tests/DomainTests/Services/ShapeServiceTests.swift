import XCTest
@testable import KanvasCore

/// `ShapeService` pure transforms: create/move/resize/style/z-order/delete. The z-order tests pin
/// the key design rule — shapes share the canvas `sortIndex` space with stickies, so a new or
/// re-stacked shape numbers against **both** collections.
final class ShapeServiceTests: XCTestCase {

    private var service: ShapeService!

    override func setUp() {
        super.setUp()
        service = ShapeService(repository: StubBoardRepository())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func state(stickies: [Sticky] = [], shapes: [CanvasShape] = []) -> BoardState {
        BoardState(board: Board(title: "B"), columns: [], cards: [],
                   stickies: stickies, shapes: shapes)
    }

    private func placement() -> ShapePlacement {
        ShapePlacement(position: CanvasPosition(x: 10, y: 20), size: ShapeSize(width: 100, height: 80))
    }

    // MARK: - adding

    func testAdding_appendsShapeOfRequestedKind() {
        let cardID = UUID()

        let result = service.adding(spec: ShapeSpec(kind: "ellipse", topology: .box),
                                    placement: placement(), toCardCanvas: cardID, in: state())

        XCTAssertEqual(result.shapes.first?.kind, "ellipse")
    }

    func testAdding_persistsTopology() {
        let cardID = UUID()

        let result = service.adding(spec: ShapeSpec(kind: "triangle", topology: .box),
                                    placement: placement(), toCardCanvas: cardID, in: state())

        XCTAssertEqual(result.shapes.first?.topology, .box)
    }

    func testAdding_emptyCanvas_numbersFromZero() {
        let result = service.adding(spec: ShapeSpec(kind: "rectangle", topology: .box),
                                    placement: placement(), toCardCanvas: UUID(), in: state())

        XCTAssertEqual(result.shapes.first?.sortIndex, 0)
    }

    func testAdding_numbersAboveExistingStickyOnSameCard() {
        let cardID = UUID()
        let sticky = Sticky(cardID: cardID, content: "a", position: .zero, sortIndex: 5)

        let result = service.adding(spec: ShapeSpec(kind: "rectangle", topology: .box),
                                    placement: placement(), toCardCanvas: cardID,
                                    in: state(stickies: [sticky]))

        // Shared z-order: the new shape sits above the sticky (5 → 6), not at 0.
        XCTAssertEqual(result.shapes.first?.sortIndex, 6)
    }

    // MARK: - moving

    func testMoving_updatesPosition() throws {
        let shape = CanvasShape(cardID: UUID(), kind: "rectangle", position: .zero, sortIndex: 0)

        let result = try service.moving(id: shape.id, to: CanvasPosition(x: 7, y: 9),
                                    in: state(shapes: [shape]))

        XCTAssertEqual(result.shapes.first?.position, CanvasPosition(x: 7, y: 9))
    }

    // MARK: - resizing

    private func placement(_ width: Double, _ height: Double) -> ShapePlacement {
        ShapePlacement(position: .zero, size: ShapeSize(width: width, height: height))
    }

    func testResizing_boxShape_clampsToUsableMinimum() throws {
        let shape = CanvasShape(cardID: UUID(), kind: "rectangle", topology: .box,
                                position: .zero, sortIndex: 0)

        let result = try service.resizing(id: shape.id, to: placement(1, 1),
                                      lineRising: nil, in: state(shapes: [shape]))

        XCTAssertEqual(result.shapes.first?.size,
                       ShapeSize(width: ShapeSize.minFilledSide, height: ShapeSize.minFilledSide))
    }

    func testResizing_segmentShape_allowsNearFlatBox() throws {
        // A horizontal line collapses its box height to ~0 — filled-shape minimum must not apply.
        let shape = CanvasShape(cardID: UUID(), kind: "line", topology: .segment,
                                position: .zero, sortIndex: 0)

        let result = try service.resizing(id: shape.id, to: placement(200, 0),
                                      lineRising: false, in: state(shapes: [shape]))

        XCTAssertEqual(result.shapes.first?.size.height, 0)
    }

    func testResizing_segment_recordsRisingDiagonal() throws {
        let shape = CanvasShape(cardID: UUID(), kind: "line", topology: .segment,
                                position: .zero, sortIndex: 0)

        let result = try service.resizing(id: shape.id, to: placement(100, 80),
                                      lineRising: true, in: state(shapes: [shape]))

        XCTAssertEqual(result.shapes.first?.lineRising, true)
    }

    func testResizing_segment_belowMinLength_scalesUpPreservingDirection() throws {
        // A 3-4-5 triangle box (diagonal 5 < minLineLength 8) scales up keeping its 3:4 aspect.
        let shape = CanvasShape(cardID: UUID(), kind: "line", topology: .segment,
                                position: .zero, sortIndex: 0)

        let result = try service.resizing(id: shape.id, to: placement(3, 4),
                                      lineRising: false, in: state(shapes: [shape]))

        let size = result.shapes.first?.size
        let diagonal = ((size?.width ?? 0) * (size?.width ?? 0) + (size?.height ?? 0) * (size?.height ?? 0)).squareRoot()
        XCTAssertEqual(diagonal, ShapeSize.minLineLength, accuracy: 0.001)
    }

    func testResizing_segment_fullyDegenerate_defaultsToHorizontalMinLength() throws {
        let shape = CanvasShape(cardID: UUID(), kind: "line", topology: .segment,
                                position: .zero, sortIndex: 0)

        let result = try service.resizing(id: shape.id, to: placement(0, 0),
                                      lineRising: false, in: state(shapes: [shape]))

        XCTAssertEqual(result.shapes.first?.size, ShapeSize(width: ShapeSize.minLineLength, height: 0))
    }

    func testResizing_clampsDrivenByStoredTopology_notByKind() throws {
        // A shape with kind "line" but topology .box should clamp as a box (min filled side),
        // proving the switch keys off stored topology, not visual kind.
        let shape = CanvasShape(cardID: UUID(), kind: "line", topology: .box,
                                position: .zero, sortIndex: 0)

        let result = try service.resizing(id: shape.id, to: placement(1, 1),
                                      lineRising: nil, in: state(shapes: [shape]))

        XCTAssertEqual(result.shapes.first?.size,
                       ShapeSize(width: ShapeSize.minFilledSide, height: ShapeSize.minFilledSide))
    }

    // MARK: - styling

    func testSettingFillColor_nil_clearsFill() throws {
        let shape = CanvasShape(cardID: UUID(), kind: "rectangle", position: .zero,
                                style: CanvasShapeStyle(fillColorHex: "FF0000"), sortIndex: 0)

        let result = try service.settingFillColor(id: shape.id, colorHex: nil, in: state(shapes: [shape]))

        XCTAssertNil(result.shapes.first?.style.fillColorHex)
    }

    func testSettingStrokeColor_updatesHex() throws {
        let shape = CanvasShape(cardID: UUID(), kind: "rectangle", position: .zero, sortIndex: 0)

        let result = try service.settingStrokeColor(id: shape.id, colorHex: "00FF00", in: state(shapes: [shape]))

        XCTAssertEqual(result.shapes.first?.style.strokeColorHex, "00FF00")
    }

    func testSettingStrokeWidth_clampsAboveMaximum() throws {
        let shape = CanvasShape(cardID: UUID(), kind: "rectangle", position: .zero, sortIndex: 0)

        let result = try service.settingStrokeWidth(id: shape.id, width: 9999, in: state(shapes: [shape]))

        XCTAssertEqual(result.shapes.first?.style.strokeWidth, CanvasShapeStyle.maxStrokeWidth)
    }

    // MARK: - z-order (shared with stickies)

    func testBringingToFront_liftsAboveAFrontmostSticky() throws {
        let cardID = UUID()
        let shape = CanvasShape(cardID: cardID, kind: "rectangle", position: .zero, sortIndex: 0)
        let sticky = Sticky(cardID: cardID, content: "a", position: .zero, sortIndex: 3)

        let result = try service.bringingToFront(id: shape.id, in: state(stickies: [sticky], shapes: [shape]))

        XCTAssertEqual(result.shapes.first?.sortIndex, 4)
    }

    func testSendingToBack_dropsBelowABackmostSticky() throws {
        let cardID = UUID()
        let shape = CanvasShape(cardID: cardID, kind: "rectangle", position: .zero, sortIndex: 0)
        let sticky = Sticky(cardID: cardID, content: "a", position: .zero, sortIndex: -2)

        let result = try service.sendingToBack(id: shape.id, in: state(stickies: [sticky], shapes: [shape]))

        XCTAssertEqual(result.shapes.first?.sortIndex, -3)
    }

    // MARK: - deleting

    func testDeleting_removesTheShape() throws {
        let shape = CanvasShape(cardID: UUID(), kind: "rectangle", position: .zero, sortIndex: 0)

        let result = try service.deleting(id: shape.id, from: state(shapes: [shape]))

        XCTAssertTrue(result.shapes.isEmpty)
    }

    func testDeleting_unknownID_throwsNotFound() {
        let missingID = UUID()

        XCTAssertThrowsError(try service.deleting(id: missingID, from: state(shapes: []))) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Shape", id: missingID))
        }
    }
}
