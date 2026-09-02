# review-checklist バインディング（kanvas）

グローバルスキル `~/.claude/skills/review-checklist/SKILL.md` の7項目枠組みに、kanvas（Swift / macOS app + MCP サーバ）固有の語彙を与える。各フィールドは正準の所在を指す（内容の転記は正準文書が無い場合のみ）。

## 必須フィールド

1. **例外体系** — `Sources/Error/` の ValidationError / OperationError（いずれも LocalizedError）。最外殻変換点は `Sources/MCP/main.swift` の CallTool ハンドラ（`errorText()` が `LocalizedError.errorDescription` を優先して `isError` テキスト化）。外部境界（ファイル I/O・JSON decode 等）のエラーはこの体系へ翻訳してから投げる。
2. **両側テストが要る抽象境界** — `Sources/Infrastructure/Protocols/InfrastructureProtocols.swift` の protocol 群（一層一ファイルに集約）と Domain/UseCase の protocol 境界（実装数は概ね N=1 + fake）。fake/stub の所在は `Tests/Support/`（InMemoryBoardStore・StubBoardRepository・各 UseCase stub 等）。
3. **入力検証イディオム** — 書き込み経路の入力検証は **UseCase 層の Request**（`Sources/UseCase/Requests/*`）で行い ValidationError を throw する（Request 層が検証境界であることは `ContentSizeValidation.swift` の doc コメントが明言）。上限値の正準は `ContentSizeValidation` / `NumericBoundsValidation`（いずれも `Sources/UseCase/Requests/`。`Sources/Constants/` に上限値は無い）。数値の再クランプは Domain entity の init にも存在する（例: `CanvasTextStyle.fontSize`、`CanvasShapeStyle.strokeWidth` — domain rule としてのクランプ）。新規 String/Data 入力フィールドは Request 層に空値・形式・サイズ検証を置く（項目5の Swift 側対応）。Domain Services での ValidationError throw は例外的（現状 `ConnectorService.swift` のみ）。
4. **並行書き込み機構** — FileLock（flock。唯一の呼び出し site は `JSONBoardStore.withExclusiveAccess` で、app と KanvasMCP サーバの read-modify-write をプロセス間で直列化）。**ボードスナップショット**（JSONBoardStore が管理する store ファイル群）への新規書き込みサイトを JSONBoardStore の外に作らない。既存の設計上の例外: `MarkdownJournalStore`（`markdown-journal/<cardID>.json` — カード単位 atomic 上書き・flock/undo の帯域外に置く意図的設計）。新規の帯域外永続書き込みを増やす場合は、項目7でその TOCTOU 検討を明示する。BoardStoreWriteLedger は並行制御ではなく watcher の自己エコー抑制 — スナップショットへの新規書き込み経路を作る場合は `recordSelfWrite` の呼び漏れも項目7で確認する。
5. **機械強制済み除外** — `.swiftlint.yml` の custom_rules（レイヤー import 方向・単一モジュールの型参照ガード・safety escape hatch 禁止）と Phase 3 複雑度ルール。正準は `.swiftlint.yml`。
6. **レイヤー定義の正準の所在** — `.swiftlint.yml` のコメントと custom_rules（Presentation → UseCase → Domain → Repository → Infrastructure。Error / Constants / Utils は Foundation-only の leaf）。
7. **CI フロア** — `Scripts/build.sh --test`（`swift test` は `--test` 指定時のみ実行され、その後 release build — 素の `build.sh` はテストを走らせない）と、swiftlint の手動起動（設定は `.swiftlint.yml`。どのスクリプトにも配線されていない）。
8. **ルール文書の所在** — 独立したルール文書（CLAUDE.md 等）は無し。ただし `.swiftlint.yml` のコメント散文（`# Architecture:` で始まるレイヤー順コメント、`presentation_no_appkit` ルール直前の Presentation 例外説明ブロック等 — 後者は現に `arch-presentation.md` への dangling 参照を含む）は陳腐化しうるルール記述であり、kanvas の項目4(c) は**この `.swiftlint.yml` コメント群を確認対象として適用する**（恒久 N/A とはしない）。独立ルール文書を将来設けた場合はこのフィールドを更新する。
