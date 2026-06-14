import XCTest
@testable import KanvasCore

/// Tests for `CardMetadataEditor.ExternalScheduleRewrite` — the pure gate deciding whether
/// an externally rewritten schedule (e.g. `board_card_edit` via MCP, surfaced through
/// `BoardStoreWatcher` → `selectedCardDetail`) is adopted into the schedule edit buffers.
///
/// The contract (follow-up to PR #38, which covered the Markdown notes):
/// - Schedule edits commit synchronously on every control change, so no dirty-buffer state
///   survives — the gate only distinguishes "genuinely new" from "already represented".
/// - A self-echo of our own commit compares equal to the buffers and is NOT adopted.
/// - An external clear (nil) over a set schedule is a legitimate new state.
final class CardMetadataExternalReseedTests: XCTestCase {

    private let day1 = Date(timeIntervalSinceReferenceDate: 0)
    private let day2 = Date(timeIntervalSinceReferenceDate: 86_400)
    private let day3 = Date(timeIntervalSinceReferenceDate: 172_800)

    func testAdoptsExternalDeadlineDifferingFromLocal() {
        XCTAssertTrue(
            CardMetadataEditor.ExternalScheduleRewrite(
                newSchedule: .deadline(day2),
                localSchedule: .deadline(day1)
            ).shouldAdopt
        )
    }

    func testIgnoresSelfEchoOfOwnDeadlineCommit() {
        // commitScheduleIfChanged persists the buffers; the watcher then reloads the detail
        // with an identical schedule — adopting it would be pointless churn.
        XCTAssertFalse(
            CardMetadataEditor.ExternalScheduleRewrite(
                newSchedule: .deadline(day1),
                localSchedule: .deadline(day1)
            ).shouldAdopt
        )
    }

    func testAdoptsExternalClearOverSetSchedule() {
        XCTAssertTrue(
            CardMetadataEditor.ExternalScheduleRewrite(
                newSchedule: nil,
                localSchedule: .deadline(day1)
            ).shouldAdopt
        )
    }

    func testIgnoresWhenBothUnscheduled() {
        XCTAssertFalse(
            CardMetadataEditor.ExternalScheduleRewrite(
                newSchedule: nil,
                localSchedule: nil
            ).shouldAdopt
        )
    }

    func testAdoptsExternalModeSwitchFromDeadlineToPeriod() {
        XCTAssertTrue(
            CardMetadataEditor.ExternalScheduleRewrite(
                newSchedule: .period(start: day1, end: day3),
                localSchedule: .deadline(day2)
            ).shouldAdopt
        )
    }

    func testIgnoresEquivalentPeriod() {
        XCTAssertFalse(
            CardMetadataEditor.ExternalScheduleRewrite(
                newSchedule: .period(start: day1, end: day2),
                localSchedule: .period(start: day1, end: day2)
            ).shouldAdopt
        )
    }

    func testAdoptsPeriodEndChangeAlone() {
        // The period cases compare both bounds — a single-bound rewrite is still new.
        XCTAssertTrue(
            CardMetadataEditor.ExternalScheduleRewrite(
                newSchedule: .period(start: day1, end: day3),
                localSchedule: .period(start: day1, end: day2)
            ).shouldAdopt
        )
    }

    func testAdoptsPeriodStartChangeAlone() {
        // A change to only the start bound is also new — both bounds are compared.
        XCTAssertTrue(
            CardMetadataEditor.ExternalScheduleRewrite(
                newSchedule: .period(start: day2, end: day3),
                localSchedule: .period(start: day1, end: day3)
            ).shouldAdopt
        )
    }
}
