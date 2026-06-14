import Foundation

extension BoardSnapshotMapper {

    static func settingsEntity(_ dto: BoardSettingsDTO?) -> BoardSettings {
        guard let dto else { return .default }
        return BoardSettings(
            global: globalSettingsEntity(dto.global),
            board: boardTabSettingsEntity(dto.board),
            canvas: canvasSettingsEntity(dto.canvas),
            markdown: markdownSettingsEntity(dto.markdown)
        )
    }

    static func settingsDTO(_ settings: BoardSettings) -> BoardSettingsDTO {
        BoardSettingsDTO(
            global: GlobalSettingsDTO(
                backgroundColorHex: settings.global.backgroundColorHex,
                textColorHex: settings.global.textColorHex,
                colorPalette: settings.global.colorPalette.map(paletteColorDTO)
            ),
            board: BoardTabSettingsDTO(
                cardSortPolicy: settings.board.cardSortPolicy.rawValue,
                autoCompleteOnMove: settings.board.autoCompleteOnMove,
                cardBackgroundColorHex: settings.board.cardBackgroundColorHex,
                cardTextColorHex: settings.board.cardTextColorHex,
                cardBorderColorHex: settings.board.cardBorderColorHex,
                textColorHex: settings.board.textColorHex,
                newCardPosition: settings.board.newCardPosition.rawValue
            ),
            canvas: CanvasSettingsDTO(
                stickyPresets: settings.canvas.stickyPresets.map(stickyPresetDTO),
                defaultFontSize: settings.canvas.defaultFontSize,
                defaultTextColorHex: settings.canvas.defaultTextColorHex,
                freeStickyColorHex: settings.canvas.freeStickyColorHex,
                taskStickyColorHex: settings.canvas.taskStickyColorHex,
                initialZoomScale: settings.canvas.initialZoomScale,
                gridSnapInterval: settings.canvas.gridSnapInterval
            ),
            markdown: MarkdownSettingsDTO(
                baseFontSize: settings.markdown.baseFontSize,
                headingSizes: settings.markdown.headingSizes,
                codeColorHex: settings.markdown.codeColorHex,
                quoteColorHex: settings.markdown.quoteColorHex,
                useMonospacedFont: settings.markdown.useMonospacedFont,
                codeBlockBackgroundColorHex: settings.markdown.codeBlockBackgroundColorHex,
                quoteBorderColorHex: settings.markdown.quoteBorderColorHex,
                quoteBorderWidth: settings.markdown.quoteBorderWidth,
                linkColorHex: settings.markdown.linkColorHex,
                editorBackgroundColorHex: settings.markdown.editorBackgroundColorHex,
                listIndentExtra: settings.markdown.listIndentExtra,
                listItemSpacing: settings.markdown.listItemSpacing,
                lineSpacing: settings.markdown.lineSpacing,
                syntaxColorOverrides: settings.markdown.syntaxColorOverrides
            )
        )
    }
}

private extension BoardSnapshotMapper {

    static func globalSettingsEntity(_ dto: GlobalSettingsDTO?) -> GlobalSettings {
        guard let dto else { return .default }
        // A nil palette (snapshot predating the field) falls back to the seeded set; a
        // present-but-empty array is preserved as the user's deliberate "clear all".
        let palette = dto.colorPalette?.map(paletteColorEntity)
        return GlobalSettings(
            backgroundColorHex: dto.backgroundColorHex,
            textColorHex: dto.textColorHex,
            colorPalette: palette ?? GlobalSettings.default.colorPalette
        )
    }

    /// DTO → entity for one palette colour. A nil id mints a fresh one; the raw persisted colour is
    /// passed straight through — `PaletteColor.init` validates the hex (and falls back to its
    /// `defaultColorHex` for an absent/malformed value) and truncates the label. No domain decision
    /// lives here.
    static func paletteColorEntity(_ dto: PaletteColorDTO) -> PaletteColor {
        PaletteColor(
            id: dto.id ?? UUID(),
            colorHex: dto.colorHex ?? "",
            label: dto.label ?? ""
        )
    }

    /// Entity → DTO for one palette colour (no normalisation — the entity already holds valid
    /// values).
    static func paletteColorDTO(_ color: PaletteColor) -> PaletteColorDTO {
        PaletteColorDTO(id: color.id, colorHex: color.colorHex, label: color.label)
    }

    static func boardTabSettingsEntity(_ dto: BoardTabSettingsDTO?) -> BoardTabSettings {
        guard let dto else { return .default }
        let d = BoardTabSettings.default
        let policy = dto.cardSortPolicy.flatMap { CardSortPolicy(rawValue: $0) }
        let position = dto.newCardPosition.flatMap { NewCardPosition(rawValue: $0) }
        return BoardTabSettings(
            cardSortPolicy: policy ?? d.cardSortPolicy,
            autoCompleteOnMove: dto.autoCompleteOnMove ?? d.autoCompleteOnMove,
            cardBackgroundColorHex: dto.cardBackgroundColorHex,
            cardTextColorHex: dto.cardTextColorHex,
            cardBorderColorHex: dto.cardBorderColorHex,
            textColorHex: dto.textColorHex,
            newCardPosition: position ?? d.newCardPosition
        )
    }

    static func canvasSettingsEntity(_ dto: CanvasSettingsDTO?) -> CanvasSettings {
        guard let dto else { return .default }
        let d = CanvasSettings.default
        // A nil or empty preset list (snapshot predating the field, or all presets deleted then
        // reloaded) falls back to the seeded S/M/L set so the palette is never empty.
        let presets = dto.stickyPresets?.map(stickyPresetEntity)
        return CanvasSettings(
            stickyPresets: (presets?.isEmpty == false) ? presets! : d.stickyPresets,
            defaultFontSize: dto.defaultFontSize ?? d.defaultFontSize,
            // A legacy "auto" value is coerced to the default inside CanvasSettings.init.
            defaultTextColorHex: dto.defaultTextColorHex ?? d.defaultTextColorHex,
            freeStickyColorHex: dto.freeStickyColorHex,
            taskStickyColorHex: dto.taskStickyColorHex,
            initialZoomScale: dto.initialZoomScale ?? d.initialZoomScale,
            gridSnapInterval: dto.gridSnapInterval ?? d.gridSnapInterval
        )
    }

    /// DTO → entity for one preset. A nil id mints a fresh one; a missing field of a partial /
    /// corrupt persisted preset falls back to a Domain default (`StickyPreset.defaultFillHex` for
    /// colour, `StickySize.default` for size) — single-sourced so it can't drift from the seed.
    /// The entity `init` re-clamps size + truncates the label.
    static func stickyPresetEntity(_ dto: StickyPresetDTO) -> StickyPreset {
        StickyPreset(
            id: dto.id ?? UUID(),
            label: dto.label ?? "",
            colorHex: dto.colorHex ?? StickyPreset.defaultFillHex,
            width: dto.width ?? StickySize.default.width,
            height: dto.height ?? StickySize.default.height
        )
    }

    /// Entity → DTO for one preset (no clamping — the entity already holds valid values).
    static func stickyPresetDTO(_ preset: StickyPreset) -> StickyPresetDTO {
        StickyPresetDTO(
            id: preset.id,
            label: preset.label,
            colorHex: preset.colorHex,
            width: preset.width,
            height: preset.height
        )
    }

    static func markdownSettingsEntity(_ dto: MarkdownSettingsDTO?) -> MarkdownSettings {
        guard let dto else { return .default }
        let d = MarkdownSettings.default
        return MarkdownSettings(
            baseFontSize: dto.baseFontSize ?? d.baseFontSize,
            headingSizes: dto.headingSizes ?? MarkdownSettings.defaultHeadingSizes,
            codeColorHex: dto.codeColorHex,
            quoteColorHex: dto.quoteColorHex,
            useMonospacedFont: dto.useMonospacedFont ?? d.useMonospacedFont,
            codeBlockBackgroundColorHex: dto.codeBlockBackgroundColorHex,
            quoteBorderColorHex: dto.quoteBorderColorHex,
            quoteBorderWidth: dto.quoteBorderWidth ?? d.quoteBorderWidth,
            linkColorHex: dto.linkColorHex,
            editorBackgroundColorHex: dto.editorBackgroundColorHex,
            listIndentExtra: dto.listIndentExtra ?? d.listIndentExtra,
            listItemSpacing: dto.listItemSpacing ?? d.listItemSpacing,
            lineSpacing: dto.lineSpacing ?? d.lineSpacing,
            syntaxColorOverrides: dto.syntaxColorOverrides ?? d.syntaxColorOverrides
        )
    }
}
