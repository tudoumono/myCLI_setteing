# setupScript

AI CLI運用（Claude/Codex/Gemini）向けの統合スクリプト置き場です。

## 目的

- エージェントを切り替えても、最小限の共通設定を維持する
- MCP設定を一元管理する
- 変更を `Global / Project / Local` のレイヤーで扱う
- 壊れたときに `reset` ですぐ戻せるようにする

## メインスクリプト

- `update-ai-clis.sh`

対応:
- CLI更新（npm）
- 共通設定の同期（sync）
- 差分確認（diff / --dry-run）
- 共通設定のリセット（reset）
- 状態確認（status）
- Skills共通化（`ai-config/skills` を正本として各CLIへコピー配布）
- グローバル指示配布（`ai-config/global-instructions.md` を各CLIへ配布）
- ベースロック更新（lock-base）
- PJ初期化（project-init）
- PJフォルダ基準の簡易実行（sync-here/status-here/reset-here/all-here）

詳細な実行例は `USAGE.md` を参照してください。

## 設定ファイル

- `ai-config/base.json`: 固定ベース
- `ai-config/base.lock.sha256`: `base.json` のロック
- `ai-config/projects/*.json`: PJ差分
- `ai-config/local.json`: マシン固有差分（任意）
- `ai-config/skills/`: スキル共通化のマスター（配布元）
- `ai-config/global-instructions.md`: グローバル指示マスター（存在時のみ配布）
- `<project>/.ai-stack.local.json`: フォルダ固有差分（任意）

## 実行場所のルール

- 全体管理（`init`, `lock-base`）: `setupScript` フォルダ
- PJ運用（`project-init`, `sync-here`, `status-here`, `diff`）: PJフォルダ

これで「1つのシェルでディレクトリを行き来する」運用を減らせます。

## 重要ポリシー

- `base.json` は最小の共通ベースとして固定
- 追加機能は `projects/*.json` で管理
- `sync/reset/status` は `base.json` 改変を検知したら停止
- 意図的な改変時のみ `lock-base` でハッシュ更新

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

## ドリフト検知（CI向け）

```bash
./update-ai-clis.sh check
```

master と配布先が不一致なら非0終了。cron/CIでドリフト検知に使えます。

## statusで確認できるもの

- MCP有効数（Codex/Claude/Gemini）
- Skills数 + sha256ハッシュ（master/Claude）
- Global instructions の有無 + ハッシュ + レイヤー情報

## テスト

```bash
./tests/smoke.sh
./tests/full-smoke.sh
```

- `tests/smoke.sh`: 最小限の安全なスモークテスト（テンポラリ環境）
- `tests/full-smoke.sh`: 詳細スモークテスト（skills / instructions / drift / dry-run 検証、テンポラリ環境）
