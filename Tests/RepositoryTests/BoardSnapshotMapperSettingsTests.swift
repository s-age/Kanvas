import XCTest
@testable import KanvasCore

final class BoardSnapshotMapperSettingsTests: XCTestCase {

    private func emptySnapshot(settings: BoardSettingsDTO? = nil) -> BoardSnapshotDTO {
        BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"),
            columns: [], cards: [], stickies: [],
            settings: settings
        )
    }

    // MARK: - Nil / legacy snapshots → defaults

    func testToEntities_nilSettings_decodesToDefault() {
        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(emptySnapshot(settings: nil))

        XCTAssertEqual(state.settings, BoardSettings.default)
    }

    /// Builds a canvas DTO with only `stickyPresets` varying (every other field nil).
    private func canvasDTO(stickyPresets: [StickyPresetDTO]?) -> CanvasSettingsDTO {
        CanvasSettingsDTO(
            stickyPresets: stickyPresets, defaultFontSize: nil, defaultTextColorHex: nil,
            freeStickyColorHex: nil, taskStickyColorHex: nil, initialZoomScale: nil, gridSnapInterval: nil
        )
    }

    private func settingsDTO(canvas: CanvasSettingsDTO) -> BoardSettingsDTO {
        BoardSettingsDTO(global: nil, board: nil, canvas: canvas, markdown: nil)
    }

    func testToEntities_partialStickyPreset_fillsMissingFieldsFromDomainDefaults() {
        // A corrupt/partial preset (only an id) recovers its colour from StickyPreset.defaultFillHex
        // and its size from StickySize.default — single-sourced, so no drift from the seed.
        let partial = StickyPresetDTO(id: UUID(), label: nil, colorHex: nil, width: nil, height: nil)
        let settings = settingsDTO(canvas: canvasDTO(stickyPresets: [partial]))

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(emptySnapshot(settings: settings))

        let preset = state.settings.canvas.stickyPresets.first
        XCTAssertEqual(preset?.colorHex, StickyPreset.defaultFillHex)
        XCTAssertEqual(preset?.width, StickySize.default.width)
        XCTAssertEqual(preset?.height, StickySize.default.height)
    }

    func testToEntities_legacyAutoDefaultTextColor_migratesToConcreteDefault() {
        var canvas = canvasDTO(stickyPresets: nil)
        canvas.defaultTextColorHex = "auto"  // the retired sentinel
        let settings = settingsDTO(canvas: canvas)

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(emptySnapshot(settings: settings))

        XCTAssertEqual(state.settings.canvas.defaultTextColorHex, StickyTextStyle.defaultColorHex)
    }

    func testToEntities_nilStickyPresets_fallsBackToSeededDefaults() {
        // A snapshot predating the preset field (canvas present, stickyPresets nil) must seed S/M/L
        // so the palette is never empty.
        let settings = settingsDTO(canvas: canvasDTO(stickyPresets: nil))

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(emptySnapshot(settings: settings))

        XCTAssertEqual(state.settings.canvas.stickyPresets, StickyPreset.defaultPresets)
    }

    func testToEntities_emptyStickyPresets_fallsBackToSeededDefaults() {
        let settings = settingsDTO(canvas: canvasDTO(stickyPresets: []))

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(emptySnapshot(settings: settings))

        XCTAssertEqual(state.settings.canvas.stickyPresets, StickyPreset.defaultPresets)
    }

    func testToEntities_emptySubDTOs_decodesToDefaults() {
        let dto = BoardSettingsDTO(global: nil, board: nil, canvas: nil, markdown: nil)

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(emptySnapshot(settings: dto))

        XCTAssertEqual(state.settings.global, GlobalSettings.default)
        XCTAssertEqual(state.settings.board, BoardTabSettings.default)
        XCTAssertEqual(state.settings.canvas, CanvasSettings.default)
        XCTAssertEqual(state.settings.markdown, MarkdownSettings.default)
    }

    // MARK: - Round-trip

    func testRoundTrip_preservesGlobalSettings() {
        let settings = BoardSettings(
            global: GlobalSettings(backgroundColorHex: "1A2B3C", textColorHex: "FFFFFF")
        )
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.settings = settings

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.settings.global.backgroundColorHex, "1A2B3C")
        XCTAssertEqual(restored.settings.global.textColorHex, "FFFFFF")
    }

    func testRoundTrip_preservesColorPalette() {
        let palette = [
            PaletteColor(colorHex: "112233", label: "One"),
            PaletteColor(colorHex: "445566", label: ""),
        ]
        let settings = BoardSettings(global: GlobalSettings(colorPalette: palette))
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.settings = settings

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.settings.global.colorPalette, palette)
    }

    func testColorPalette_emptyArrayIsPreservedNotReseeded() {
        let settings = BoardSettings(global: GlobalSettings(colorPalette: []))
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.settings = settings

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertTrue(restored.settings.global.colorPalette.isEmpty)
    }

    func testColorPalette_nilDTOSeedsDefaultPalette() {
        let dto = BoardSettingsDTO(global: GlobalSettingsDTO(colorPalette: nil))
        let entity = BoardSnapshotMapper.settingsEntity(dto)

        XCTAssertEqual(entity.global.colorPalette, PaletteColor.defaultPalette)
    }

    func testRoundTrip_preservesBoardTabSettings() {
        let settings = BoardSettings(
            board: BoardTabSettings(
                cardSortPolicy: .titleAscending,
                autoCompleteOnMove: false,
                cardBackgroundColorHex: "112233",
                cardTextColorHex: "445566",
                newCardPosition: .top
            )
        )
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.settings = settings

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.settings.board.cardSortPolicy, .titleAscending)
        XCTAssertEqual(restored.settings.board.autoCompleteOnMove, false)
        XCTAssertEqual(restored.settings.board.cardBackgroundColorHex, "112233")
        XCTAssertEqual(restored.settings.board.cardTextColorHex, "445566")
        XCTAssertEqual(restored.settings.board.newCardPosition, .top)
    }

    func testRoundTrip_preservesCanvasSettings() {
        let presets = [
            StickyPreset(label: "XS", colorHex: "112233", width: 120, height: 90),
            StickyPreset(label: "XL", colorHex: "445566", width: 400, height: 300),
        ]
        let settings = BoardSettings(
            canvas: CanvasSettings(
                stickyPresets: presets,
                defaultFontSize: 18,
                defaultTextColorHex: "FF0000",
                freeStickyColorHex: "00FF00",
                taskStickyColorHex: "0000FF",
                initialZoomScale: 1.5,
                gridSnapInterval: 20
            )
        )
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.settings = settings

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.settings.canvas.stickyPresets, presets)
        XCTAssertEqual(restored.settings.canvas.defaultFontSize, 18)
        XCTAssertEqual(restored.settings.canvas.defaultTextColorHex, "FF0000")
        XCTAssertEqual(restored.settings.canvas.freeStickyColorHex, "00FF00")
        XCTAssertEqual(restored.settings.canvas.taskStickyColorHex, "0000FF")
        XCTAssertEqual(restored.settings.canvas.initialZoomScale, 1.5)
        XCTAssertEqual(restored.settings.canvas.gridSnapInterval, 20)
    }

    func testRoundTrip_preservesMarkdownSettings() {
        let sizes: [Double] = [30, 26, 22, 18, 16, 14]
        let settings = BoardSettings(
            markdown: MarkdownSettings(
                baseFontSize: 16,
                headingSizes: sizes,
                codeColorHex: "AABB00",
                quoteColorHex: "00AABB",
                useMonospacedFont: true
            )
        )
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.settings = settings

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.settings.markdown.baseFontSize, 16)
        XCTAssertEqual(restored.settings.markdown.headingSizes, sizes)
        XCTAssertEqual(restored.settings.markdown.codeColorHex, "AABB00")
        XCTAssertEqual(restored.settings.markdown.quoteColorHex, "00AABB")
        XCTAssertEqual(restored.settings.markdown.useMonospacedFont, true)
    }

    func testRoundTrip_preservesMarkdownBlockDecorationSettings() {
        let settings = BoardSettings(
            markdown: MarkdownSettings(
                codeBlockBackgroundColorHex: "161B22",
                quoteBorderColorHex: "3B434B",
                quoteBorderWidth: 5,
                linkColorHex: "4493F8"
            )
        )
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.settings = settings

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.settings.markdown.codeBlockBackgroundColorHex, "161B22")
        XCTAssertEqual(restored.settings.markdown.quoteBorderColorHex, "3B434B")
        XCTAssertEqual(restored.settings.markdown.quoteBorderWidth, 5)
        XCTAssertEqual(restored.settings.markdown.linkColorHex, "4493F8")
    }

    func testMarkdownSettings_nilBlockDecorationFields_fallBackToDefaults() {
        // A snapshot predating the block-decoration fields (nil values in DTO) must decode cleanly
        // and use domain defaults — no migration needed.
        let boardDTO = BoardSettingsDTO(
            global: nil,
            board: nil,
            canvas: nil,
            markdown: MarkdownSettingsDTO(
                baseFontSize: 14,
                headingSizes: MarkdownSettings.defaultHeadingSizes,
                codeColorHex: nil,
                quoteColorHex: nil,
                useMonospacedFont: false
                // Block-decoration fields absent — not provided to the initializer.
            )
        )
        let settings = BoardSnapshotMapper.settingsEntity(boardDTO)

        XCTAssertNil(settings.markdown.codeBlockBackgroundColorHex)
        XCTAssertNil(settings.markdown.quoteBorderColorHex)
        XCTAssertEqual(settings.markdown.quoteBorderWidth, MarkdownSettings.defaultQuoteBorderWidth)
        XCTAssertNil(settings.markdown.linkColorHex)
    }

    func testRoundTrip_preservesSyntaxColorOverrides() {
        let overrides = ["keyword": "112233", "string": "445566"]
        let settings = BoardSettings(markdown: MarkdownSettings(syntaxColorOverrides: overrides))
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.settings = settings

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.settings.markdown.syntaxColorOverrides, overrides)
    }

    func testMarkdownSettings_nilSyntaxColorOverrides_decodesToEmpty() {
        // A snapshot predating the field (nil in DTO) must decode to the empty map (built-in palette).
        let boardDTO = BoardSettingsDTO(
            global: nil,
            board: nil,
            canvas: nil,
            markdown: MarkdownSettingsDTO(baseFontSize: 14)
            // syntaxColorOverrides absent.
        )
        let settings = BoardSnapshotMapper.settingsEntity(boardDTO)
        XCTAssertEqual(settings.markdown.syntaxColorOverrides, [:])
    }

    func testRoundTrip_defaultSettings_survivesRoundTrip() {
        let state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.settings, BoardSettings.default)
    }

    // MARK: - Paragraph-styling round-trip

    func testRoundTrip_preservesMarkdownParagraphStylingSettings() {
        let settings = BoardSettings(
            markdown: MarkdownSettings(
                editorBackgroundColorHex: "0D1117",
                listIndentExtra: 8,
                listItemSpacing: 4,
                lineSpacing: 5
            )
        )
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.settings = settings

        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(BoardSnapshotMapper.toDTO(state))

        XCTAssertEqual(restored.settings.markdown.editorBackgroundColorHex, "0D1117")
        XCTAssertEqual(restored.settings.markdown.listIndentExtra, 8)
        XCTAssertEqual(restored.settings.markdown.listItemSpacing, 4)
        XCTAssertEqual(restored.settings.markdown.lineSpacing, 5)
    }

    func testMarkdownSettings_nilParagraphStylingFields_fallBackToDefaults() {
        // A snapshot predating paragraph-styling fields decodes cleanly using domain defaults.
        let boardDTO = BoardSettingsDTO(
            global: nil,
            board: nil,
            canvas: nil,
            markdown: MarkdownSettingsDTO(
                baseFontSize: 14,
                headingSizes: MarkdownSettings.defaultHeadingSizes,
                codeColorHex: nil,
                quoteColorHex: nil,
                useMonospacedFont: false
                // Paragraph-styling fields absent — not provided to the initializer.
            )
        )
        let settings = BoardSnapshotMapper.settingsEntity(boardDTO)

        XCTAssertNil(settings.markdown.editorBackgroundColorHex)
        XCTAssertEqual(settings.markdown.listIndentExtra, 0)
        XCTAssertEqual(settings.markdown.listItemSpacing, 0)
        XCTAssertEqual(settings.markdown.lineSpacing, MarkdownSettings.defaultLineSpacing)
    }
}
