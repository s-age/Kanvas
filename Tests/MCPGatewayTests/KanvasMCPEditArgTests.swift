import XCTest
@testable import KanvasCore

/// Tests for `KanvasMCPGateway.requestEdit` / `scheduleEdit` — the pure mappings that pin an
/// omittable `board_card_edit` tool argument onto `EditCardRequest`'s keep/clear/set
/// double-optionals. The dangerous failure mode is optional *promotion*: handing a `T?` straight
/// to a `T??` parameter wraps the whole optional, so nil (keep) silently becomes `.some(nil)`
/// (clear). These tests fail if a future cleanup reintroduces that promotion.
final class KanvasMCPEditArgTests: XCTestCase {

    // MARK: - requestEdit (assignee-style String argument)

    func testRequestEditKeepsOnOmittedArgument() {
        let value: String?? = KanvasMCPGateway.requestEdit(nil)
        guard case .none = value else {
            return XCTFail("Omitted argument must map to outer nil (keep), got \(String(describing: value))")
        }
    }

    func testRequestEditSetsProvidedValue() {
        let value: String?? = KanvasMCPGateway.requestEdit("s-age")
        guard case .some(.some(let assignee)) = value else {
            return XCTFail("Provided argument must map to .some(.some), got \(String(describing: value))")
        }
        XCTAssertEqual(assignee, "s-age")
    }

    func testRequestEditCarriesEmptyStringForDownstreamClear() {
        // The empty string is not collapsed here — blank→nil clearing is EditCardUseCaseImpl's
        // canonical normalization; this boundary must deliver it intact.
        let value: String?? = KanvasMCPGateway.requestEdit("")
        guard case .some(.some(let assignee)) = value else {
            return XCTFail("Empty string must map to .some(.some(\"\")), got \(String(describing: value))")
        }
        XCTAssertEqual(assignee, "")
    }

    // MARK: - scheduleEdit (parse + pin in one step)

    func testScheduleEditKeepsOnOmittedArgument() throws {
        let value = try KanvasMCPGateway.scheduleEdit(nil)
        guard case .none = value else {
            return XCTFail("Omitted argument must map to outer nil (keep), got \(String(describing: value))")
        }
    }

    func testScheduleEditClearsOnNone() throws {
        let value = try KanvasMCPGateway.scheduleEdit("none")
        guard case .some(.none) = value else {
            return XCTFail("'none' must map to .some(nil) (clear), got \(String(describing: value))")
        }
    }

    func testScheduleEditSetsParsedDeadline() throws {
        let value = try KanvasMCPGateway.scheduleEdit("2026-06-10")
        guard case .some(.some(.deadline(let date))) = value else {
            return XCTFail("Date string must map to .some(.some(.deadline)), got \(String(describing: value))")
        }
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 10
        XCTAssertEqual(date, Calendar.current.date(from: components))
    }
}
