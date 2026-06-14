import Foundation
import XCTest
@testable import KanvasCore

/// `ContentSizeValidation` caps caller-supplied free text and image bytes at the Request boundary so
/// a model cannot bloat the whole-blob JSON store. Each request that carries one of these bounds is
/// exercised at its own length/byte limit and one past it.
final class ContentSizeValidationTests: XCTestCase {

    private func string(_ count: Int) -> String { String(repeating: "x", count: count) }

    // MARK: - title bound (card / board / column)

    func testAddCard_titleAtLimit_passes() throws {
        try AddCardRequest(title: string(ContentSizeValidation.maxTitleLength), columnID: UUID()).validate()
    }

    func testAddCard_titleOverLimit_throwsTitleTooLong() {
        let request = AddCardRequest(title: string(ContentSizeValidation.maxTitleLength + 1), columnID: UUID())
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .titleTooLong(max: ContentSizeValidation.maxTitleLength))
        }
    }

    func testRenameColumn_titleOverLimit_throwsTitleTooLong() {
        let request = RenameColumnRequest(columnID: UUID(), title: string(ContentSizeValidation.maxTitleLength + 1))
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .titleTooLong(max: ContentSizeValidation.maxTitleLength))
        }
    }

    // MARK: - markdown bound

    func testAddCard_markdownAtLimit_passes() throws {
        try AddCardRequest(
            title: "ok", columnID: UUID(),
            markdownContent: string(ContentSizeValidation.maxMarkdownLength)
        ).validate()
    }

    func testEditCard_markdownOverLimit_throwsContentTooLong() {
        let request = EditCardRequest(
            cardID: UUID(),
            markdownContent: string(ContentSizeValidation.maxMarkdownLength + 1)
        )
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .contentTooLong(max: ContentSizeValidation.maxMarkdownLength))
        }
    }

    // MARK: - assignee bound

    func testEditCard_assigneeAtLimit_passes() throws {
        try EditCardRequest(
            cardID: UUID(),
            assignee: .some(string(ContentSizeValidation.maxAssigneeLength))
        ).validate()
    }

    func testEditCard_assigneeOverLimit_throwsContentTooLong() {
        let request = EditCardRequest(
            cardID: UUID(),
            assignee: .some(string(ContentSizeValidation.maxAssigneeLength + 1))
        )
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .contentTooLong(max: ContentSizeValidation.maxAssigneeLength))
        }
    }

    func testEditCard_clearAssignee_passes() throws {
        // `.some(.none)` clears the field — nothing to cap.
        try EditCardRequest(cardID: UUID(), assignee: .some(nil)).validate()
    }

    // MARK: - PR URL bound

    func testEditCard_prURLOverLimit_throwsContentTooLong() {
        let request = EditCardRequest(
            cardID: UUID(),
            prURL: .some(string(ContentSizeValidation.maxURLLength + 1))
        )
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .contentTooLong(max: ContentSizeValidation.maxURLLength))
        }
    }

    // MARK: - sticky content bound

    func testAddSticky_emptyContent_passes() throws {
        try AddStickyRequest(
            cardID: UUID(), content: "",
            positionX: 0, positionY: 0, width: 100, height: 100, fillColorHex: nil
        ).validate()
    }

    func testEditSticky_contentOverLimit_throwsContentTooLong() {
        let request = EditStickyRequest(
            stickyID: UUID(),
            content: string(ContentSizeValidation.maxStickyContentLength + 1)
        )
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .contentTooLong(max: ContentSizeValidation.maxStickyContentLength))
        }
    }

    // MARK: - image byte bound

    func testAddImage_atByteLimit_passes() throws {
        try AddImageRequest(
            cardID: UUID(), imageData: Data(count: ContentSizeValidation.maxImageByteCount),
            positionX: 0, positionY: 0, naturalWidth: 100, naturalHeight: 100
        ).validate()
    }

    func testAddImage_overByteLimit_throwsImageDataTooLarge() {
        let request = AddImageRequest(
            cardID: UUID(), imageData: Data(count: ContentSizeValidation.maxImageByteCount + 1),
            positionX: 0, positionY: 0, naturalWidth: 100, naturalHeight: 100
        )
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .imageDataTooLarge(maxBytes: ContentSizeValidation.maxImageByteCount))
        }
    }
}
