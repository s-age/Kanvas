import XCTest
@testable import KanvasCore

/// Tests for `KanvasMCPGateway.scheduleValue` — the parser behind `board_card_edit`'s
/// `schedule` argument: "none" clears, "YYYY-MM-DD" is a deadline, "YYYY-MM-DD/YYYY-MM-DD"
/// is a period. Dates resolve to local midnight (matching the app's date pickers).
final class KanvasMCPScheduleArgTests: XCTestCase {

    private func localMidnight(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    func testParsesNoneAsClear() throws {
        XCTAssertNil(try KanvasMCPGateway.scheduleValue("none"))
    }

    func testParsesSingleDateAsDeadlineAtLocalMidnight() throws {
        XCTAssertEqual(
            try KanvasMCPGateway.scheduleValue("2026-06-10"),
            .deadline(localMidnight(year: 2026, month: 6, day: 10))
        )
    }

    func testParsesSlashSeparatedDatesAsPeriod() throws {
        XCTAssertEqual(
            try KanvasMCPGateway.scheduleValue("2026-06-01/2026-06-10"),
            .period(
                start: localMidnight(year: 2026, month: 6, day: 1),
                end: localMidnight(year: 2026, month: 6, day: 10)
            )
        )
    }

    func testThrowsOnUnparseableDate() {
        XCTAssertThrowsError(try KanvasMCPGateway.scheduleValue("tomorrow")) { error in
            guard case KanvasMCPError.badSchedule(let value) = error else {
                return XCTFail("Expected badSchedule, got \(error)")
            }
            XCTAssertEqual(value, "tomorrow")
        }
    }

    func testThrowsOnTooManySegments() {
        XCTAssertThrowsError(try KanvasMCPGateway.scheduleValue("2026-06-01/2026-06-10/2026-06-20")) { error in
            guard case KanvasMCPError.badSchedule = error else {
                return XCTFail("Expected badSchedule, got \(error)")
            }
        }
    }

    func testThrowsOnEmptyPeriodSegment() {
        // omittingEmptySubsequences: false keeps "2026-06-01/" two segments, so the blank
        // end date fails date parsing instead of silently collapsing to a deadline.
        XCTAssertThrowsError(try KanvasMCPGateway.scheduleValue("2026-06-01/")) { error in
            guard case KanvasMCPError.badSchedule = error else {
                return XCTFail("Expected badSchedule, got \(error)")
            }
        }
    }
}
