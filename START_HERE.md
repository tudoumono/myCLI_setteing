# START HERE

このドキュメントは、`setupScript` を初めて触る人向けの最短ガイドです。

## これは何をするプロジェクトか

- Claude/Codex/Gemini の設定を1つのレジストリ（`ai-config/`）でまとめて管理します。
- `sync` で3CLIへ同じ方針を配布し、`reset` でベース状態に戻せます。
- 設定は `Global / Project / Local / Folder local` の4レイヤーで上書きできます。

## 先に知っておくこと

- このスクリプトは `~/.claude.json`、`~/.claude/settings.json`、`~/.codex/config.toml`、`~/.gemini/settings.json` を更新します。
- `reset` は npm/pipx の MCP パッケージをアンインストール対象として処理します。
- 実行前の設定は `ai-config/backups/<timestamp>/` にバックアップされます。

## 必要環境

- Bash
- Node.js
- npm
- pipx（pipxパッケージを扱う場合のみ）

## 最短セットアップ（5分）

```bash
cd /path/to/setupScript
./update-ai-clis.sh init
./update-ai-clis.sh sync
./update-ai-clis.sh status
./update-ai-clis.sh check
```

これで「共通ベース設定の初期化・配布・確認」まで完了します。

## よく使う運用パターン

### 1) 既存PJへ設定を反映

```bash
./update-ai-clis.sh sync my-project
```

### 2) PJフォルダで安全に運用（推奨）

```bash
cd /path/to/my-project
/path/to/setupScript/update-ai-clis.sh project-init
/path/to/setupScript/update-ai-clis.sh status-here
/path/to/setupScript/update-ai-clis.sh sync-here
```

`project-init` では以下も自動作成されます:
- `.ai-stack.local.json`（フォルダ固有設定）
- `BACKLOG.md`（条件付きで後でやる案の管理）

### 3) 変更内容を先に確認

```bash
./update-ai-clis.sh diff my-project
./update-ai-clis.sh sync my-project --dry-run
./update-ai-clis.sh reset my-project --dry-run
```

## コマンド早見表

- `init`: `ai-config/` の必須ファイルを作成
- `sync`: レイヤーをマージして3CLIへ配布
- `reset`: ベースへ戻す（設定 + skills/instructions 再配布 + MCPアンインストール処理）
- `status`: 現在状態の可視化（layers、MCP数、skillsハッシュ等）
- `check`: skills / global instructions のドリフト検知
- `diff`: `sync` した場合の差分プレビュー
- `all`: `update` + `sync`

## 学びの扱い（kb と skill）

- `kb` 更新はラフに速く進める
  - `kb-candidate`: 事実・手順・知見の追記候補
  - 承認後は `sync-knowledge` フローで更新
- `skill` 更新は精査して進める
  - `skill-candidate`: 繰り返す作業フローの候補
  - 承認は草案作成まで。最終反映は再承認
- 1セッションあたりの提案上限
  - `kb-candidate` 最大1件
  - `skill-candidate` 最大1件

## 初見でハマりやすい点

- 引数なしで `./update-ai-clis.sh` を実行すると `update` が走ります。
- `sync/reset/diff/check/status` で `[project]` を省略した場合、フォルダローカル設定は `実行中ディレクトリ/.ai-stack.local.json` が使われます。
- `check` は skills と global instructions の整合確認が対象です。MCP設定ファイル全体は比較しません。
- `BACKLOG.md` は運用メモ用で、`sync/reset` でCLIに配布される設定ファイルではありません。

## どのドキュメントを読むべきか

- 全体概要: `README.md`
- 詳細コマンド: `USAGE.md`
- レイヤー定義: `ai-config/README.md`
- テスト: `tests/smoke.sh` / `tests/full-smoke.sh`
