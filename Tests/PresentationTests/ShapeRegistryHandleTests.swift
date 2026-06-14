import AppKit
import XCTest
@testable import KanvasCore

/// The closure-driven handle specs `ShapeRegistry.defaultHandles(for:)` returns — the pure
/// interaction geometry behind the canvas's unified drag loop (concern C). Asserts handle counts,
/// positions, and the raw (unclamped) frame + `rising` each handle requests. Clamp/snap are the
/// canvas/domain's job and are not exercised here.
@MainActor
final class ShapeRegistryHandleTests: XCTestCase {

    // MARK: - defaultHandles

    func testDefaultHandles_box_isSingleCornerHandle() {
        XCTAssertEqual(ShapeRegistry.defaultHandles(for: .box).count, 1)
    }

    func testDefaultHandles_segment_isTwoEndpointHandles() {
        XCTAssertEqual(ShapeRegistry.defaultHandles(for: .segment).count, 2)
    }

    // MARK: - Box corner handle

    func testBoxCornerHandle_positionIsBottomRight() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 60)
        let pos = ShapeRegistry.boxCornerHandle.position(frame, (start: .zero, end: .zero))
        XCTAssertEqual(pos, CGPoint(x: frame.maxX, y: frame.maxY))
    }

    func testBoxCornerHandle_requestedDrag_keepsTopLeftFixed_sizesToCursor() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 60)
        // Drag the bottom-right corner to (160, 200): top-left stays at (10,20).
        let request = ShapeRegistry.boxCornerHandle.requestedDrag(
            CGPoint(x: 160, y: 200), frame, (start: .zero, end: .zero))
        XCTAssertEqual(request.worldFrame, CGRect(x: 10, y: 20, width: 150, height: 180))
        XCTAssertNil(request.rising, "Box corner resize never sets lineRising")
    }

    // MARK: - Segment endpoint handles

    func testSegmentStartHandle_positionIsStartEndpoint() {
        let ends = (start: CGPoint(x: 5, y: 6), end: CGPoint(x: 30, y: 40))
        let pos = ShapeRegistry.segmentStartHandle.position(.zero, ends)
        XCTAssertEqual(pos, ends.start)
    }

    func testSegmentEndHandle_positionIsEndEndpoint() {
        let ends = (start: CGPoint(x: 5, y: 6), end: CGPoint(x: 30, y: 40))
        let pos = ShapeRegistry.segmentEndHandle.position(.zero, ends)
        XCTAssertEqual(pos, ends.end)
    }

    func testSegmentStartHandle_requestedDrag_boundsAgainstFixedEndEndpoint() {
        let ends = (start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100))
        // Drag the start endpoint to (40, 130); the end (100,100) stays fixed.
        let request = ShapeRegistry.segmentStartHandle.requestedDrag(
            CGPoint(x: 40, y: 130), .zero, ends)
        XCTAssertEqual(request.worldFrame, CGRect(x: 40, y: 100, width: 60, height: 30))
    }

    func testSegmentEndHandle_requestedDrag_boundsAgainstFixedStartEndpoint() {
        let ends = (start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100))
        // Drag the end endpoint to (40, 130); the start (0,0) stays fixed.
        let request = ShapeRegistry.segmentEndHandle.requestedDrag(
            CGPoint(x: 40, y: 130), .zero, ends)
        XCTAssertEqual(request.worldFrame, CGRect(x: 0, y: 0, width: 40, height: 130))
    }

    // The flipped view means "rising" (right end higher on screen) is right.y < left.y.
    func testSegmentEndHandle_requestedDrag_risingTrue_whenDraggedEndIsHigher() {
        let ends = (start: CGPoint(x: 0, y: 100), end: CGPoint(x: 100, y: 100))
        // Fixed start at (0,100); drag the end up-screen to (100, 20) → right end higher → rising.
        let request = ShapeRegistry.segmentEndHandle.requestedDrag(
            CGPoint(x: 100, y: 20), .zero, ends)
        XCTAssertEqual(request.rising, true)
    }

    func testSegmentEndHandle_requestedDrag_risingFalse_whenDraggedEndIsLower() {
        let ends = (start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        // Fixed start at (0,0); drag the end down-screen to (100, 80) → right end lower → not rising.
        let request = ShapeRegistry.segmentEndHandle.requestedDrag(
            CGPoint(x: 100, y: 80), .zero, ends)
        XCTAssertEqual(request.rising, false)
    }
}
