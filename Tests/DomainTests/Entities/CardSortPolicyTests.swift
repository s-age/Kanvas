import XCTest
@testable import KanvasCore

/// `CardSortPolicy.ordered` is the single source of card display order. Each policy is pinned,
/// including the `sortIndex` tiebreaker that keeps ordering deterministic (Swift's sort is not
/// guaranteed stable and legacy cards share a `.distantPast` timestamp).
final class CardSortPolicyTests: XCTestCase {

    private let columnID = UUID()

    private func card(
        _ title: String,
        createdAt: Date = .distantPast,
        sortIndex: Int
    ) -> Card {
        Card(columnID: columnID, title: title, createdAt: createdAt, sortIndex: sortIndex)
    }

    // MARK: - manual

    func testOrdered_manual_sortsBySortIndex() {
        let cards = [card("b", sortIndex: 2), card("a", sortIndex: 0), card("c", sortIndex: 1)]

        let ordered = CardSortPolicy.manual.ordered(cards)

        XCTAssertEqual(ordered.map(\.title), ["a", "c", "b"])
    }

    // MARK: - titleAscending

    func testOrdered_titleAscending_sortsCaseInsensitively() {
        let cards = [card("banana", sortIndex: 0), card("Apple", sortIndex: 1), card("cherry", sortIndex: 2)]

        let ordered = CardSortPolicy.titleAscending.ordered(cards)

        XCTAssertEqual(ordered.map(\.title), ["Apple", "banana", "cherry"])
    }

    func testOrdered_titleAscending_breaksTieBySortIndex() {
        let cards = [card("same", sortIndex: 5), card("same", sortIndex: 1)]

        let ordered = CardSortPolicy.titleAscending.ordered(cards)

        XCTAssertEqual(ordered.map(\.sortIndex), [1, 5])
    }

    // MARK: - createdNewest / createdOldest

    func testOrdered_createdNewest_putsLatestFirst() {
        let cards = [
            card("old", createdAt: Date(timeIntervalSince1970: 100), sortIndex: 0),
            card("new", createdAt: Date(timeIntervalSince1970: 300), sortIndex: 1),
            card("mid", createdAt: Date(timeIntervalSince1970: 200), sortIndex: 2),
        ]

        let ordered = CardSortPolicy.createdNewest.ordered(cards)

        XCTAssertEqual(ordered.map(\.title), ["new", "mid", "old"])
    }

    func testOrdered_createdOldest_putsEarliestFirst() {
        let cards = [
            card("old", createdAt: Date(timeIntervalSince1970: 100), sortIndex: 0),
            card("new", createdAt: Date(timeIntervalSince1970: 300), sortIndex: 1),
            card("mid", createdAt: Date(timeIntervalSince1970: 200), sortIndex: 2),
        ]

        let ordered = CardSortPolicy.createdOldest.ordered(cards)

        XCTAssertEqual(ordered.map(\.title), ["old", "mid", "new"])
    }

    func testOrdered_createdNewest_breaksEqualTimestampBySortIndex() {
        let cards = [card("b", sortIndex: 2), card("a", sortIndex: 0)]

        let ordered = CardSortPolicy.createdNewest.ordered(cards)

        XCTAssertEqual(ordered.map(\.sortIndex), [0, 2])
    }
}
