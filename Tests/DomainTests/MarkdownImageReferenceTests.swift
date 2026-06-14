import XCTest
@testable import KanvasCore

/// `MarkdownImageReference` — the shared `kanvas-asset://` vocabulary used by the editor (build/parse)
/// and the orphan GC (extract every referenced id from a body). The `referencedAssetIDs` cases pin
/// the GC's reachability hinge (ticket BF5746C8): a reference must yield its id, junk must not.
final class MarkdownImageReferenceTests: XCTestCase {

    func testMarkdown_buildsStandardImageReference() {
        let id = UUID()
        XCTAssertEqual(MarkdownImageReference.markdown(for: id),
                       "![](kanvas-asset://\(id.uuidString))")
    }

    func testAssetIDFromURL_parsesSchemeURL() {
        let id = UUID()
        XCTAssertEqual(MarkdownImageReference.assetID(fromURL: "kanvas-asset://\(id.uuidString)"), id)
    }

    func testAssetIDFromURL_rejectsForeignScheme() {
        XCTAssertNil(MarkdownImageReference.assetID(fromURL: "https://example.com/x.png"))
    }

    func testReferencedAssetIDs_findsSingleReference() {
        let id = UUID()
        let body = "intro\n\(MarkdownImageReference.markdown(for: id))\noutro"
        XCTAssertEqual(MarkdownImageReference.referencedAssetIDs(in: body), [id])
    }

    func testReferencedAssetIDs_findsMultipleAndDeduplicates() {
        let a = UUID()
        let b = UUID()
        let body = """
        \(MarkdownImageReference.markdown(for: a))
        \(MarkdownImageReference.markdown(for: b))
        \(MarkdownImageReference.markdown(for: a))
        """
        XCTAssertEqual(MarkdownImageReference.referencedAssetIDs(in: body), [a, b])
    }

    func testReferencedAssetIDs_emptyForBodyWithoutScheme() {
        XCTAssertTrue(MarkdownImageReference.referencedAssetIDs(in: "plain text, no images").isEmpty)
    }

    func testReferencedAssetIDs_ignoresSchemeWithMalformedUUID() {
        // The scheme is present but the id is not a valid UUID — must not yield a phantom id.
        XCTAssertTrue(MarkdownImageReference.referencedAssetIDs(in: "kanvas-asset://not-a-uuid").isEmpty)
    }

    func testReferencedAssetIDs_matchesEvenWithCustomAltText() {
        // The GC keys off the URL, not the `![]( … )` wrapper, so an edited alt text still counts.
        let id = UUID()
        XCTAssertEqual(
            MarkdownImageReference.referencedAssetIDs(in: "![my diagram](kanvas-asset://\(id.uuidString))"),
            [id]
        )
    }

    // MARK: - per-image width (ticket 4103CA3F)

    func testMarkdown_withWidth_appendsWidthQuery() {
        let id = UUID()
        XCTAssertEqual(MarkdownImageReference.markdown(for: id, width: 200),
                       "![](kanvas-asset://\(id.uuidString)?w=200)")
    }

    func testMarkdown_withNilWidth_isByteIdenticalToUnsizedReference() {
        // An unsized reference must be unchanged from the pre-4103CA3F form (no query suffix).
        let id = UUID()
        XCTAssertEqual(MarkdownImageReference.markdown(for: id, width: nil),
                       "![](kanvas-asset://\(id.uuidString))")
    }

    func testMarkdown_withNonPositiveWidth_omitsTheQuery() {
        let id = UUID()
        XCTAssertEqual(MarkdownImageReference.markdown(for: id, width: 0),
                       "![](kanvas-asset://\(id.uuidString))")
    }

    func testMarkdown_withFractionalWidth_keepsTheDecimal() {
        let id = UUID()
        XCTAssertEqual(MarkdownImageReference.markdown(for: id, width: 150.5),
                       "![](kanvas-asset://\(id.uuidString)?w=150.5)")
    }

    func testDisplayWidthFromURL_parsesWidthQuery() {
        let id = UUID()
        XCTAssertEqual(MarkdownImageReference.displayWidth(fromURL: "kanvas-asset://\(id.uuidString)?w=200"), 200)
    }

    func testDisplayWidthFromURL_nilForUnsizedURL() {
        let id = UUID()
        XCTAssertNil(MarkdownImageReference.displayWidth(fromURL: "kanvas-asset://\(id.uuidString)"))
    }

    func testDisplayWidthFromURL_nilForNonPositiveWidth() {
        let id = UUID()
        XCTAssertNil(MarkdownImageReference.displayWidth(fromURL: "kanvas-asset://\(id.uuidString)?w=0"))
    }

    func testDisplayWidthFromURL_nilForMalformedWidth() {
        let id = UUID()
        XCTAssertNil(MarkdownImageReference.displayWidth(fromURL: "kanvas-asset://\(id.uuidString)?w=abc"))
    }

    func testAssetIDFromURL_toleratesWidthQuery() {
        // A sized URL must still yield its asset id (the width is ignored here).
        let id = UUID()
        XCTAssertEqual(MarkdownImageReference.assetID(fromURL: "kanvas-asset://\(id.uuidString)?w=200"), id)
    }

    func testReferencedAssetIDs_findsSizedReference() {
        // The orphan GC must still reach an asset whose reference carries a width suffix.
        let id = UUID()
        let body = "before\n\(MarkdownImageReference.markdown(for: id, width: 320))\nafter"
        XCTAssertEqual(MarkdownImageReference.referencedAssetIDs(in: body), [id])
    }

    func testReferencedAssetIDs_findsReferenceWithMalformedWidthSuffix() {
        // A malformed `?w=abc` suffix must not hide the asset from the GC, and the reference scanner's
        // shared URL grammar must still match the whole reference so it degrades to fit-width rather
        // than rendering as raw source (finding r1-3).
        let id = UUID()
        let body = "![](kanvas-asset://\(id.uuidString)?w=abc)"
        XCTAssertEqual(MarkdownImageReference.referencedAssetIDs(in: body), [id])
    }

    func testURLByApplyingWidth_setsWidthOnUnsizedURL() {
        let id = UUID()
        let url = "kanvas-asset://\(id.uuidString)"
        XCTAssertEqual(MarkdownImageReference.url(byApplyingWidth: 200, to: url),
                       "kanvas-asset://\(id.uuidString)?w=200")
    }

    func testURLByApplyingWidth_replacesExistingWidth() {
        let id = UUID()
        let url = "kanvas-asset://\(id.uuidString)?w=200"
        XCTAssertEqual(MarkdownImageReference.url(byApplyingWidth: 100, to: url),
                       "kanvas-asset://\(id.uuidString)?w=100")
    }

    func testURLByApplyingWidth_nilClearsExistingWidth() {
        let id = UUID()
        let url = "kanvas-asset://\(id.uuidString)?w=200"
        XCTAssertEqual(MarkdownImageReference.url(byApplyingWidth: nil, to: url),
                       "kanvas-asset://\(id.uuidString)")
    }

    func testURLByApplyingWidth_leavesForeignSchemeUnchanged() {
        let url = "https://example.com/image.png"
        XCTAssertEqual(MarkdownImageReference.url(byApplyingWidth: 200, to: url), url)
    }

    // MARK: - removingFirstReference (ticket 2A2784BE)

    func testRemovingFirstReference_removesSoleReference() {
        let id = UUID()
        // The add paths insert `\n<ref>\n`, so the own-line form is the realistic input.
        let body = "intro\n\(MarkdownImageReference.markdown(for: id))\noutro"

        let result = MarkdownImageReference.removingFirstReference(to: id, in: body)

        // The reference and its own-line wrapping newline collapse, leaving no blank line.
        XCTAssertEqual(result, "intro\noutro")
    }

    func testRemovingFirstReference_removesOnlyTheFirstOfDuplicates() {
        let id = UUID()
        let reference = MarkdownImageReference.markdown(for: id)
        let body = "\(reference)\n\(reference)"

        let result = MarkdownImageReference.removingFirstReference(to: id, in: body)

        // Exactly one reference remains (the refcount semantics: drop one, keep the rest).
        XCTAssertEqual(result, reference)
    }

    func testRemovingFirstReference_removesSizedReference() {
        let id = UUID()
        let body = "![](kanvas-asset://\(id.uuidString)?w=200)"

        let result = MarkdownImageReference.removingFirstReference(to: id, in: body)

        XCTAssertEqual(result, "")
    }

    func testRemovingFirstReference_removesReferenceWithAltAndTitleWrapper() {
        let id = UUID()
        let body = "![diagram](kanvas-asset://\(id.uuidString) \"My title\")"

        let result = MarkdownImageReference.removingFirstReference(to: id, in: body)

        XCTAssertEqual(result, "")
    }

    func testRemovingFirstReference_matchesLowercasedID() {
        let id = UUID()
        let body = "![](kanvas-asset://\(id.uuidString.lowercased()))"

        let result = MarkdownImageReference.removingFirstReference(to: id, in: body)

        XCTAssertEqual(result, "")
    }

    func testRemovingFirstReference_returnsNilWhenAbsent() {
        let present = UUID()
        let absent = UUID()
        let body = MarkdownImageReference.markdown(for: present)

        XCTAssertNil(MarkdownImageReference.removingFirstReference(to: absent, in: body))
    }

    func testRemovingFirstReference_returnsNilForBodyWithoutScheme() {
        XCTAssertNil(MarkdownImageReference.removingFirstReference(to: UUID(), in: "plain notes"))
    }

    func testRemovingFirstReference_collapsesLeadingNewlineWhenNoTrailingOne() {
        let id = UUID()
        // No trailing newline after the reference (it sits at the body's end) — the leading newline
        // is consumed instead, so no blank line is left dangling above.
        let body = "intro\n\(MarkdownImageReference.markdown(for: id))"

        let result = MarkdownImageReference.removingFirstReference(to: id, in: body)

        XCTAssertEqual(result, "intro")
    }
}
