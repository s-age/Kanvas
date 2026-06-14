import XCTest
@testable import KanvasCore

/// The canvas coordinate / offset finiteness guard (ticket 4FD6D166). Positions and offsets are
/// clamped *nowhere* on the entity path, so the Request layer is the only line of defence against a
/// boundary-less MCP caller (`canvas_sticky_move` etc.) persisting `NaN`/`±Inf` into the whole-blob
/// store. `validate()` is synchronous, so `XCTAssertThrowsError` applies.
final class CoordinateFinitenessRequestValidationTests: XCTestCase {

    // MARK: - AddStickyRequest

    func testAddSticky_finite_passes() throws {
        try AddStickyRequest(
            cardID: UUID(), content: "", positionX: 10, positionY: -20,
            width: 100, height: 100, fillColorHex: nil
        ).validate()
    }

    func testAddSticky_nonFinitePosition_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try AddStickyRequest(
                cardID: UUID(), content: "", positionX: .nan, positionY: 0,
                width: 100, height: 100, fillColorHex: nil
            ).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    // MARK: - AddTextRequest

    func testAddText_nonFinitePosition_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try AddTextRequest(
                cardID: UUID(), content: "", positionX: 0, positionY: .infinity,
                width: 100, height: 100
            ).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    // MARK: - AddImageRequest

    func testAddImage_nonFinitePosition_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try AddImageRequest(
                cardID: UUID(), imageData: Data([0x1]), positionX: -.infinity, positionY: 0,
                naturalWidth: 100, naturalHeight: 100
            ).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    // MARK: - AddShapeRequest

    func testAddShape_nonFinitePosition_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try AddShapeRequest(
                cardID: UUID(), kind: "rectangle", topology: "box",
                positionX: .nan, positionY: .nan, width: 100, height: 100
            ).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    // MARK: - MoveStickyRequest

    func testMoveSticky_finite_passes() throws {
        try MoveStickyRequest(stickyID: UUID(), positionX: 10, positionY: -20).validate()
    }

    func testMoveSticky_nanX_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try MoveStickyRequest(stickyID: UUID(), positionX: .nan, positionY: 0).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    func testMoveSticky_infiniteY_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try MoveStickyRequest(stickyID: UUID(), positionX: 0, positionY: .infinity).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    // MARK: - MoveTextRequest

    func testMoveText_negativeInfinity_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try MoveTextRequest(textID: UUID(), positionX: 0, positionY: -.infinity).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    // MARK: - MoveShapeRequest

    func testMoveShape_nan_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try MoveShapeRequest(shapeID: UUID(), positionX: .nan, positionY: .nan).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    // MARK: - MoveImageRequest

    func testMoveImage_finite_passes() throws {
        try MoveImageRequest(imageID: UUID(), positionX: 0, positionY: 0).validate()
    }

    func testMoveImage_infiniteX_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try MoveImageRequest(imageID: UUID(), positionX: .infinity, positionY: 0).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    // MARK: - SetStickyFrameRequest

    func testSetStickyFrame_nonFinitePosition_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try SetStickyFrameRequest(
                stickyID: UUID(), width: 100, height: 100, positionX: .nan, positionY: 0
            ).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    func testSetStickyFrame_nonFiniteSizeButFinitePosition_passes() throws {
        // Width/height are clamped on the StickySize entity init, so a non-finite *size* is
        // intentionally not rejected here — only position finiteness is the Request's concern.
        try SetStickyFrameRequest(
            stickyID: UUID(), width: .nan, height: .infinity, positionX: 5, positionY: 5
        ).validate()
    }

    // MARK: - ResizeTextRequest / ResizeShapeRequest / ResizeImageRequest

    func testResizeText_nonFinitePosition_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try ResizeTextRequest(
                textID: UUID(), width: 100, height: 100, positionX: 0, positionY: .nan
            ).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    func testResizeShape_nonFinitePosition_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try ResizeShapeRequest(
                shapeID: UUID(), width: 100, height: 100,
                positionX: .infinity, positionY: 0, lineRising: nil
            ).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    func testResizeImage_nonFinitePosition_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try ResizeImageRequest(
                imageID: UUID(), width: 100, height: 100, positionX: .nan, positionY: 0
            ).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    // MARK: - MoveCanvasGroupRequest

    func testMoveCanvasGroup_allFinite_passes() throws {
        try MoveCanvasGroupRequest(
            movements: [
                .init(id: UUID(), positionX: 1, positionY: 2),
                .init(id: UUID(), positionX: -3, positionY: 4),
            ],
            cardID: UUID()
        ).validate()
    }

    func testMoveCanvasGroup_emptyMovements_passes() throws {
        try MoveCanvasGroupRequest(movements: [], cardID: UUID()).validate()
    }

    func testMoveCanvasGroup_oneNonFiniteMovement_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try MoveCanvasGroupRequest(
                movements: [
                    .init(id: UUID(), positionX: 1, positionY: 2),
                    .init(id: UUID(), positionX: .nan, positionY: 4),
                ],
                cardID: UUID()
            ).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    // MARK: - SetConnectorWaypointRequest

    func testSetConnectorWaypoint_finiteOffset_passes() throws {
        try SetConnectorWaypointRequest(connectorID: UUID(), offsetX: 3, offsetY: -4).validate()
    }

    func testSetConnectorWaypoint_nonFiniteOffset_throwsNonFiniteCoordinate() {
        XCTAssertThrowsError(
            try SetConnectorWaypointRequest(connectorID: UUID(), offsetX: .nan, offsetY: 4).validate()
        ) { XCTAssertEqual($0 as? ValidationError, .nonFiniteCoordinate) }
    }

    func testSetConnectorWaypoint_clearedOffset_passes() throws {
        // Both nil clears the waypoint — finiteness has nothing to check.
        try SetConnectorWaypointRequest(connectorID: UUID(), offsetX: nil, offsetY: nil).validate()
    }
}
