# setupScript

AI CLI運用（Claude/Codex/Gemini）向けの統合スクリプト置き場です。
初めて使う場合は `START_HERE.md` を先に読んでください。

## 目的

- エージェントを切り替えても、最小限の共通設定を維持する
- MCP設定を一元管理する
- 変更を `Global / Project / Local` のレイヤーで扱う
- 壊れたときに `reset` ですぐ戻せるようにする

## メインスクリプト

- `update-ai-clis.sh`

対応:
- CLI更新（npm）
- 引数なし実行時の既定動作（`update`）
- 共通設定の同期（sync）
- 差分確認・実行プレビュー（diff / --dry-run）
- 共通設定のリセット（reset）
- 状態確認（status）
- Skills共通化（`ai-config/skills` を正本として各CLIへコピー配布）
- グローバル指示配布（`ai-config/global-instructions.md` を各CLIへ配布）
- ベースロック更新（lock-base）
- PJ初期化（project-init）
  - `.ai-stack.local.json` 雛形、`BACKLOG.md` 雛形、`.gitignore` 追記を自動化
- PJフォルダ基準の簡易実行（sync-here/status-here/reset-here/all-here）
- ヘルプ表示（`help` / `--help` / `-h`）

詳細な実行例は `USAGE.md` を参照してください。初学者向けの導入は `START_HERE.md` にまとめています。

## 設定ファイル

- `ai-config/base.json`: 固定ベース
- `ai-config/base.lock.sha256`: `base.json` のロック
- `ai-config/projects/*.json`: PJ差分
- `ai-config/local.json`: マシン固有差分（任意）
- `ai-config/skills/`: スキル共通化のマスター（配布元）
- `ai-config/global-instructions.md`: グローバル指示マスター（存在時のみ配布）
- `ai-config/BACKLOG.md`: setupScript 運用の保留アイデアと再検討トリガー
- `<project>/.ai-stack.local.json`: フォルダ固有差分（任意）
- `<project>/BACKLOG.md`: プロジェクト側の保留アイデア管理（`project-init` で雛形生成）

## 実行場所の推奨

- 全体管理（`init`, `lock-base`）: `setupScript` フォルダでの実行を推奨
- PJ運用（`project-init`, `sync-here`, `status-here`, `reset-here`, `all-here`）: PJフォルダで実行
- どこでも実行可（`sync`, `reset`, `all`, `diff`, `check`, `status`, `update`）: 必要に応じて `[project]` 指定や `*-here` を使い分ける

これで「1つのシェルでディレクトリを行き来する」運用を減らせます。

注意:
- `sync/reset/diff/check/status` で `[project]` を省略すると、フォルダローカルレイヤーは「実行中ディレクトリ」の `.ai-stack.local.json` が使われます。
- `sync my-project` を別フォルダから実行すると、その別フォルダ側の `.ai-stack.local.json` がレイヤーに入ります。
- `BACKLOG.md` は運用メモ用で、CLI設定へは配布されません。

## 重要ポリシー

- `base.json` は最小の共通ベースとして固定
- 追加機能は `projects/*.json` で管理
- `sync/reset/status` は `base.json` 改変を検知したら停止
- 意図的な改変時のみ `lock-base` でハッシュ更新

## 学びの更新方針（kb と skill）

- `kb-*` は知識蓄積レーン（高速更新）
  - 事実・手順・知見の追記を優先
  - 承認後は `sync-knowledge` で反映
- `skill` はワークフローレーン（精査更新）
  - 承認時点は「草案作成許可」
  - 最終反映前に再承認する運用
- `skill-discovery` の提案上限は 1セッションで `kb-candidate` 1件 + `skill-candidate` 1件

## WebSearchと言語

- Claude: `permissions.allow` に `WebSearch` を付与
- Claude: Read系は `Read/Grep/Glob/LS` を付与（`Bash(cat|ls|find|grep...)` は使わない方針）
- Codex: `[tools] web_search = true` を維持
- Gemini: `~/.gemini/settings.json` の `mcpServers` に直接反映 + managed manifest を同期
- 日本語をデフォルト方針として管理

## Skills共通化

- 正本: `ai-config/skills/`
- 配布先: `~/.claude/skills/`, `~/.gemini/skills/`, `~/.codex/skills/`
- 配布方式: コピーのみ（symlinkは使わない）
- `sync` / `reset` 実行時に自動配布

## グローバル指示ファイル

レイヤー化された指示ファイルを連結して配布します:

1. `ai-config/global-instructions.md` (ベース)
2. `ai-config/projects/<name>.instructions.md` (プロジェクト固有、任意)
3. `ai-config/global-instructions.local.md` (マシン固有、任意、gitignore対象)

存在時のみ以下へ配布:
- `~/.claude/CLAUDE.md`
- `~/.codex/AGENTS.md`
- `~/.gemini/GEMINI.md`

連結対象ファイルが1つも存在しない場合は配布を実行しません（既存の `CLAUDE.md/AGENTS.md/GEMINI.md` を自動削除もしません）。

## resetの挙動

- `reset` は認証トークンを保持したまま、設定系をベース状態へ戻します。
- `~/.gemini/mcp.managed.json` は削除されます。
- 有効レジストリに登録された npm/pipx の MCP パッケージをアンインストール対象として処理します。
- `sync` と同様に skills と global instructions の配布は実行されます。
- 事前確認は `./update-ai-clis.sh reset --dry-run` で行えます。

## ドリフト検知（CI向け）

```bash
./update-ai-clis.sh check
```

`check` は skills と global instructions の配布結果のみを比較し、不一致なら非0終了します。cron/CIで内容ドリフト検知に使えます（MCP設定ファイルの比較は対象外）。

## statusで確認できるもの

- MCP有効数（Codex/Claude/Gemini）
- Active layers（Global/Project/Local/Folder localの適用状態）
- Codex web_search の有効状態
- Gemini managed manifest の有無
- Registry enabled MCP 数（有効なMCP定義数）
- Skills数 + sha256ハッシュ（master/Claude）
- Global instructions の有無 + ハッシュ + レイヤー情報

## テスト

```bash
./tests/smoke.sh
./tests/full-smoke.sh
```

- `tests/smoke.sh`: 最小限の安全なスモークテスト（テンポラリ環境）
- `tests/full-smoke.sh`: 詳細スモークテスト（skills / instructions / drift / dry-run 検証、テンポラリ環境）
