# 使い方

`update-ai-clis.sh` は Claude/Codex/Gemini の共通ベース設定を同期・リセットするスクリプトです。
初回導入は `START_HERE.md` を参照してください。
具体的な運用シナリオは `USE_CASES.md` を参照してください。

## コマンド

```bash
./update-ai-clis.sh init
./update-ai-clis.sh lock-base
./update-ai-clis.sh project-init [project_dir]
./update-ai-clis.sh update
./update-ai-clis.sh sync [project]
./update-ai-clis.sh sync-here
./update-ai-clis.sh reset [project]
./update-ai-clis.sh reset-here
./update-ai-clis.sh all [project]
./update-ai-clis.sh all-here
./update-ai-clis.sh diff [project]
./update-ai-clis.sh check [project]
./update-ai-clis.sh status [project]
./update-ai-clis.sh status-here
./update-ai-clis.sh skill-share <skill_name>
./update-ai-clis.sh skill-share-all
./update-ai-clis.sh -h
./update-ai-clis.sh help
./update-ai-clis.sh --help
./update-ai-clis.sh update --dry-run
./update-ai-clis.sh <sync|reset|all> [project] --dry-run
./update-ai-clis.sh <sync-here|reset-here|all-here> --dry-run
./update-ai-clis.sh <skill-share|skill-share-all> --dry-run
```

- `diff`: `sync` 相当の変更予定を表示
- `check`: skills と global instructions の配布結果のみ比較し、不一致なら非0終了（CI/cron向け）
- `--dry-run`: `update/sync/reset/all`（`*-here` 含む）と `skill-share` 系で実変更なしに実行内容のみ確認
- `skill-share`: ローカルスキル1件を3CLIへ共有（managed skillは除く）
- `skill-share-all`: ローカルスキル（managed以外）を3CLIへ一括共有

## 対話UI（メニュー）

コマンドを覚えずに実行したい場合は、メニューラッパーを使えます。

```bash
./menu.sh
```

- Ubuntu標準の `whiptail` があればダイアログUIで実行されます（無い場合はテキストUI）。
- 日常メニューは「よく使う最小コマンド」のみ表示します。
- `a` で詳細メニュー（全コマンド）へ切り替えできます。
- `sync/reset/all` 系は `--dry-run` の有無を都度選択できます。
- `*-here` 系は対象ディレクトリを入力して実行できます。
- `8) ガイド` でクイックフローと注意点を確認できます。

## デフォルト動作

- 引数なしで `./update-ai-clis.sh` を実行すると `update` と同じ動作になります。

## よく使う流れ

```bash
# 初期化（初回のみ）
./update-ai-clis.sh init

# PJフォルダで1回だけ（overlay作成 + sync）
./update-ai-clis.sh project-init

# 状態確認
./update-ai-clis.sh status

# ベース + PJ設定を反映
./update-ai-clis.sh sync my-project

# 変更点だけ先に確認
./update-ai-clis.sh diff my-project
./update-ai-clis.sh sync my-project --dry-run

# CLI更新 + 同期
./update-ai-clis.sh all my-project
```

## ディレクトリ運用（分かりやすい推奨）

- `init` / `lock-base`: `/root/mywork/setupScript` でのみ実行可能（他フォルダではエラー）
- PJ作業: PJフォルダで `project-init`, `sync-here`, `status-here`, `reset-here`, `all-here` を実行
- 実行場所自由: `sync`, `reset`, `all`, `diff`, `check`, `status`, `update` はどこからでも実行可能（必要なら `[project]` を指定）

補足:
- `sync/reset/diff/check/status` で `[project]` を省略した場合、フォルダローカル設定は `現在のPWD/.ai-stack.local.json` が使われます。
- `sync <project>` を実行した場合でも、フォルダローカル設定は `<project>` ではなく `PWD` 側が優先されるケースがあります。PJフォルダで `sync-here` を使う運用が安全です。

例:

```bash
cd /root/mywork/my-new-project
/root/mywork/setupScript/update-ai-clis.sh project-init
/root/mywork/setupScript/update-ai-clis.sh status-here
```

## レイヤー優先順

1. `ai-config/base.json`（グローバル）
2. `ai-config/projects/<project>.json`（プロジェクト、任意）
3. `ai-config/local.json`（マシンローカル、任意）
4. `./.ai-stack.local.json`（フォルダローカル、任意）

後ろほど優先されます。

## ベースの運用ルール

- `ai-config/base.json` は固定ベースです（ロック対象）。
- 機能追加は `ai-config/projects/<project>.json` またはローカルオーバーレイで実施します。
- `base.json` を意図的に更新した場合のみ、以下でロックを更新します。
- 通常コマンド（`sync/reset/status/check/...`）は正本不足時に自動作成せずエラー終了します（先に `init`）。
- `lock-base` も正本不足時はエラー終了します（先に `init` で修復）。

```bash
./update-ai-clis.sh lock-base
```

## project-init の副作用

- `<project>/.ai-stack.local.json` の雛形を作成します。
- `<project>/BACKLOG.md` の雛形を作成します。
- `.gitignore` に `.ai-stack.local.json` が無ければ追記します。
- 実行後、そのまま `sync` を実行します。

`BACKLOG.md` の用途:
- 条件付きで将来実施する案を記録するためのファイルです。
- 各項目は「トリガー条件（いつ再検討するか）」を持たせる運用を推奨します。
- 設定配布対象ではないため、`sync/reset` でCLI側へはコピーされません。

## スキル共通化

- マスター: `ai-config/skills/`
- `sync` / `reset` で以下にコピー配布されます:
  - `~/.claude/skills/`
  - `~/.gemini/skills/`
  - `~/.codex/skills/`
- 配布方式はコピーのみ（シンボリックリンク不使用）

## PJ固有スキルの共有

`ai-config/skills` に入れたくないスキルは、ローカル共有コマンドで3CLI間に展開できます。

```bash
./update-ai-clis.sh skill-share my-project-skill
./update-ai-clis.sh skill-share-all
```

- `skill-share`: 指定スキルを3CLI間で共有
- `skill-share-all`: ローカルスキル（managed以外）をまとめて共有
- 同名スキルに差分がある場合は、更新時刻が最も新しいコピーを優先

## グローバル指示の共通配布

レイヤー化された指示ファイルを連結して配布します:

1. `ai-config/global-instructions.md`（ベース）
2. `ai-config/projects/<name>.instructions.md`（プロジェクト固有、任意）
3. `ai-config/global-instructions.local.md`（マシン固有、gitignore対象、任意）

ファイルが存在する場合のみ `sync` / `reset` で以下に配布:
- `~/.claude/CLAUDE.md`
- `~/.codex/AGENTS.md`
- `~/.gemini/GEMINI.md`

連結元ファイルが1つも無い場合は配布をスキップし、既存の配布先ファイルは自動削除しません。

## reset の副作用

- Codex/Claude/Gemini の設定をベース側へ戻します（認証トークンは保持）。
- `~/.gemini/mcp.managed.json` を削除します。
- レジストリ定義に基づき npm/pipx の MCP パッケージをアンインストール対象として処理します。
- `sync` と同様に skills / global instructions の再配布を行います。
- 実際の変更前に `./update-ai-clis.sh reset --dry-run` で差分確認できます。

## ドリフト検知（CI向け）

```bash
# skills / global instructions の状態を比較（非0終了でドリフト検出）
./update-ai-clis.sh check
./update-ai-clis.sh check my-project
```

## status 出力の見方

- `Skills master` / `Claude skills`: スキル数 + sha256ハッシュ
- `Gemini skills` / `Codex skills`: スキル数
- `Active layers`: 現在有効なレイヤー
- `Codex web_search`: Codexでのweb検索設定状態
- `Gemini manifest`: `~/.gemini/mcp.managed.json` の有無
- `Registry enabled MCP`: レジストリで有効なMCP数
- `Global instructions`: `present (hash:XXXX)` または `not configured`
  - `+project` / `+local` でレイヤー情報を表示

## テスト

```bash
./tests/smoke.sh
./tests/full-smoke.sh
```

- `tests/smoke.sh`: 最小限の安全なスモークテスト（テンポラリ環境）
- `tests/full-smoke.sh`: 詳細スモークテスト（skills / instructions / drift / dry-run 検証、テンポラリ環境）

## PATHについて

スクリプト先頭で以下を `export` しているため、WSLや非対話シェルでもコマンド解決しやすくしています。

```bash
${HOME}/.local/bin:${HOME}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}
```

## Claude の Read 系許可ポリシー

- `permissions.allow` に `Read/Grep/Glob/LS` を付与します。
- `Bash(cat|ls|find|grep...)` でのread許可は付与しません。
