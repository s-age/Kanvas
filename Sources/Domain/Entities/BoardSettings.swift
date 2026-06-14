struct BoardSettings: Sendable, Equatable {
    var global: GlobalSettings
    var board: BoardTabSettings
    var canvas: CanvasSettings
    var markdown: MarkdownSettings

    init(
        global: GlobalSettings = .default,
        board: BoardTabSettings = .default,
        canvas: CanvasSettings = .default,
        markdown: MarkdownSettings = .default
    ) {
        self.global = global
        self.board = board
        self.canvas = canvas
        self.markdown = markdown
    }

    static let `default` = BoardSettings()
}
