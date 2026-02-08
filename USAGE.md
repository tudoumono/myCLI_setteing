# USAGE

`update-ai-clis.sh` は Claude/Codex/Gemini の共通ベース設定を同期・リセットするスクリプトです。

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
./update-ai-clis.sh <sync|reset|all> [project] --dry-run
```

- `diff`: `sync` 相当の変更予定を表示
- `check`: master と配布先を比較し、不一致なら非0終了（CI/cron向け）
- `--dry-run`: `sync/reset/all` で実ファイル変更を行わず差分・実行内容だけ確認

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

- `init` / `lock-base`: `/root/mywork/setupScript` で実行
- PJ作業: PJフォルダで `project-init`, `sync-here`, `status-here` を実行

例:

```bash
cd /root/mywork/my-new-project
/root/mywork/setupScript/update-ai-clis.sh project-init
/root/mywork/setupScript/update-ai-clis.sh status-here
```

## レイヤー優先順

1. `ai-config/base.json` (Global)
2. `ai-config/projects/<project>.json` (Project)
3. `ai-config/local.json` (Machine local)
4. `./.ai-stack.local.json` (Folder local)

後ろほど優先されます。

## Baseの運用ルール

- `ai-config/base.json` は固定ベースです（ロック対象）。
- 機能追加は `ai-config/projects/<project>.json` またはローカルオーバーレイで実施します。
- `base.json` を意図的に更新した場合のみ、以下でロックを更新します。

```bash
./update-ai-clis.sh lock-base
```

## Skills共通化

- マスター: `ai-config/skills/`
- `sync` / `reset` で以下にコピー配布されます:
  - `~/.claude/skills/`
  - `~/.gemini/skills/`
  - `~/.codex/skills/`
- 配布方式はコピーのみ（symlink不使用）

## グローバル指示の共通配布

レイヤー化された指示ファイルを連結して配布します:

1. `ai-config/global-instructions.md` (ベース)
2. `ai-config/projects/<name>.instructions.md` (プロジェクト固有、任意)
3. `ai-config/global-instructions.local.md` (マシン固有、gitignore対象、任意)

ファイルが存在する場合のみ `sync` / `reset` で以下に配布:
- `~/.claude/CLAUDE.md`
- `~/.codex/AGENTS.md`
- `~/.gemini/GEMINI.md`

## ドリフト検知（CI向け）

```bash
# master と配布先の状態を比較（非0終了でドリフト検出）
./update-ai-clis.sh check
./update-ai-clis.sh check my-project
```

## status 出力の見方

- `Skills master` / `Claude skills`: スキル数 + sha256ハッシュ
- `Gemini skills` / `Codex skills`: スキル数
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

## ClaudeのRead系許可ポリシー

- `permissions.allow` に `Read/Grep/Glob/LS` を付与します。
- `Bash(cat|ls|find|grep...)` でのread許可は付与しません。
