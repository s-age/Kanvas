import Foundation

/// Lightweight image-format checks for MCP-minted assets. The app's drop/paste import always
/// re-encodes through `NSImage` → PNG, so it can never produce a non-PNG payload — but an MCP caller
/// hands raw bytes that are stored verbatim under a `.png` name, so the gateway validates the format
/// at the source rather than letting a mislabeled blob surface as an undecodable image at render
/// time (ticket 71A2D7D4).
enum MCPImageValidation {
    /// The 8-byte PNG file signature (`\x89PNG\r\n\x1a\n`), per the PNG spec.
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// True when `data` begins with the PNG file signature. Checks the magic bytes only — enough to
    /// reject a JPEG/GIF/arbitrary blob a caller named PNG; full chunk validation is left to the
    /// image decoder at render time.
    static func isPNG(_ data: Data) -> Bool {
        guard data.count >= pngSignature.count else { return false }
        return data.prefix(pngSignature.count).elementsEqual(pngSignature)
    }

    /// True when a base64 string of `base64Length` characters **cannot** decode to a payload within
    /// the asset size cap — a pre-decode reject so a giant input is refused on its string length
    /// alone, before `Data(base64Encoded:)` allocates the decoded blob (ticket F20D872C).
    ///
    /// The single source of the 32MB cap is `ContentSizeValidation.maxImageByteCount` (the UseCase
    /// validation boundary `SaveImageAssetRequest` enforces); this guard derives its threshold from
    /// that constant so the two can never diverge.
    ///
    /// For a base64 string of length `L` (a multiple of 4), the real decoded size is
    /// `(L / 4) * 3 - padding`, where padding ∈ {0, 1, 2}: zero `=` chars give the **maximum**
    /// `(L / 4) * 3`, and two `=` chars give the **minimum** `(L / 4) * 3 - 2`. To preserve the
    /// ticket invariant — never reject an input the UseCase would accept — this rejects only when
    /// even that minimum exceeds the cap, i.e. when *every* valid padding decodes over-cap. Inputs
    /// whose decoded size straddles the cap (the 1–2 byte window at exactly the cap) fall through to
    /// the exact byte check downstream; this is a cheap lower-bound fast-path, not a replacement.
    static func exceedsImageByteCap(base64Length: Int) -> Bool {
        // `(L / 4) * 3 - 2` is the minimum possible decode (two `=` padding chars); subtract first to
        // stay non-negative for tiny inputs where the product is below 2.
        let minimumDecodedBytes = max(0, (base64Length / 4) * 3 - 2)
        return minimumDecodedBytes > ContentSizeValidation.maxImageByteCount
    }
}
