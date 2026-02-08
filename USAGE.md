# 使い方

`update-ai-clis.sh` は Claude / Codex / Gemini の設定を統合管理するスクリプトです。

## コマンド一覧

```bash
./update-ai-clis.sh init
./update-ai-clis.sh lock-base
./update-ai-clis.sh project-init [project_dir]
./update-ai-clis.sh update
./update-ai-clis.sh sync [project]
./update-ai-clis.sh sync-here
./update-ai-clis.sh promote [project]
./update-ai-clis.sh promote-here
./update-ai-clis.sh reset [project]
./update-ai-clis.sh reset-here
./update-ai-clis.sh all [project]
./update-ai-clis.sh all-here
./update-ai-clis.sh diff [project]
./update-ai-clis.sh check [project]
./update-ai-clis.sh status [project]
./update-ai-clis.sh status-here
./update-ai-clis.sh skill-share <skill_name>
./update-ai-clis.sh skill-promote <skill_name|skill_dir>
./update-ai-clis.sh skill-share-all
./update-ai-clis.sh wipe-user
./update-ai-clis.sh reset-user
./update-ai-clis.sh -h|help|--help
```

## `sync` と `promote` の違い（重要）

- `sync`
  - 非PJ文脈: 3CLI ユーザ設定へ適用
  - PJ文脈: 警告 + 差分プレビューのみ（`~/` へは書き込まない）
- `sync-here`
  - 常に差分プレビュー専用
- `promote` / `promote-here`
  - PJを含む統合結果を 3CLI ユーザ設定へ昇格反映

## `--dry-run` 対応

以下は `--dry-run` で実変更なしプレビュー可能:

- `update`
- `sync`, `sync-here`
- `promote`, `promote-here`
- `reset`, `reset-here`
- `all`, `all-here`
- `skill-share`, `skill-promote`, `skill-share-all`
- `wipe-user`, `reset-user`

補足:
- `init`, `lock-base`, `project-init` は `--dry-run` 非対応（実行前に内容確認推奨）。

## 実行場所ルール

- `setupScript` でのみ実行:
  - `init`
  - `lock-base`
  - `reset-user`
- PJフォルダで実行:
  - `sync-here`, `promote-here`, `reset-here`, `all-here`, `status-here`
- どこでも実行可:
  - `sync`, `promote`, `reset`, `all`, `diff`, `check`, `status`, `update`

## 代表フロー

### 1) 初回導入

```bash
cd <myCLI_setteing_root>
./update-ai-clis.sh init
./update-ai-clis.sh status
```

### 2) PJ開始

```bash
./update-ai-clis.sh project-init /path/to/project
cd /path/to/project
./update-ai-clis.sh sync-here
./update-ai-clis.sh promote-here
./update-ai-clis.sh status-here
```

### 3) 差分確認だけ

```bash
./update-ai-clis.sh diff /path/to/project
./update-ai-clis.sh sync /path/to/project --dry-run
```

### 4) ユーザ設定の復元

```bash
./update-ai-clis.sh wipe-user --dry-run
./update-ai-clis.sh wipe-user
cd <myCLI_setteing_root>
./update-ai-clis.sh reset-user
```

## project-init の副作用

- `<project>/.ai-stack.local.json` 雛形作成
- `<project>/BACKLOG.md` 雛形作成
- 直後に `sync` 相当の差分プレビューを表示

## Skills 運用

- 管理対象 skill の正本: `ai-config/skills/`
- 配布先:
  - `~/.claude/skills/`
  - `~/.gemini/skills/`
  - `~/.codex/skills/`

コマンド:

```bash
# 既存ローカルスキル名を共有
./update-ai-clis.sh skill-share my-local-skill

# PJで作った skill ディレクトリを昇格
./update-ai-clis.sh skill-promote /path/to/project/my-skill

# ローカルスキル一括共有
./update-ai-clis.sh skill-share-all
```

## reset の挙動

- 設定をベース状態へ戻す（認証トークンは保持）
- `~/.gemini/mcp.managed.json` は再生成管理に戻る
- レジストリにある npm/pipx MCP パッケージをアンインストール対象として処理
- skills / global instructions を再配布

## check の範囲

`check` は以下のみを比較し、差分があれば非0で終了:

- skills 配布結果
- global instructions 配布結果

MCP 設定ファイル全体の比較は対象外です。

## status の見どころ

- Active layers
- MCP数（Claude/Codex/Gemini）
- Codex `web_search` 状態
- Skills数/ハッシュ
- Drift状態（Claude/Codex/Gemini）

## menu.sh

```bash
./menu.sh
```

- 日常メニューから `sync-here` / `promote-here` / `status-here` を実行可能
- `a` で詳細メニューへ切り替え
- `--dry-run` 実行を対話で選択可能
