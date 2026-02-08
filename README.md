# setupScript

Claude / Codex / Gemini の設定を、1つの正本（`ai-config/`）から管理するためのスクリプト群です。

## コンセプト

- 共有するのは Git 管理の正本設定（`ai-config/*`）だけ。
- PJ 固有設定は PJ フォルダ側で作り、必要時だけユーザ設定へ昇格する。
- PJ から `~/` 配下へ自動反映しない。反映は `promote` / `promote-here` で明示的に行う。
- 例外として初期導入と復元は `init` / `reset-user` でまとめて反映する。

## メインスクリプト

- `update-ai-clis.sh`
- 対話ラッパー: `menu.sh`

## 主要コマンドの役割

| 操作 | 目的 | `~/` 配下へ書き込み |
|---|---|---|
| `init` | 正本初期化 + ユーザ設定へ初回反映 | する |
| `project-init` | PJ の管理ファイル作成 + 差分プレビュー | しない |
| `sync` | 非PJ文脈: 3CLI 設定の共通化を適用 / PJ文脈: プレビューのみ | 条件付き |
| `sync-here` | PJ文脈の差分確認（プレビュー専用） | しない |
| `promote` / `promote-here` | 統合設定を 3CLI ユーザ設定へ昇格反映 | する |
| `reset` / `reset-here` | ユーザ設定をベース状態へ戻す | する |
| `wipe-user` | ユーザ設定を完全削除 | する（削除） |
| `reset-user` | Git 管理状態へユーザ設定を復元（`init` 相当） | する |

補足:
- `sync` は PJ 文脈（`[project]` 指定、または PJ内 `.ai-stack.local.json` が有効）では警告付きプレビューになります。
- PJ を実際に反映したい場合は `promote*` を使います。

## クイックスタート

1. 正本リポジトリを手動で clone
2. `setupScript` へ移動して初期化

```bash
cd <myCLI_setteing_root>
./update-ai-clis.sh init
./update-ai-clis.sh status
```

3. PJ開始時

```bash
./update-ai-clis.sh project-init /path/to/project
cd /path/to/project
./update-ai-clis.sh sync-here        # 変更確認のみ
./update-ai-clis.sh promote-here     # 反映したい時だけ
./update-ai-clis.sh status-here
```

## 設定ファイル

- `ai-config/base.json`: 共通ベース（ロック対象）
- `ai-config/base.lock.sha256`: `base.json` のロックハッシュ
- `ai-config/projects/<name>.json`: 旧来互換の PJ オーバーレイ（任意）
- `ai-config/local.json`: マシンローカルオーバーレイ（任意、通常はコミットしない）
- `<project>/.ai-stack.local.json`: PJローカルオーバーレイ（任意、コミット可）
- `<project>/.ai-stack.instructions.md`: PJローカル指示（任意、コミット可）
- `ai-config/skills/`: 管理対象 skill の正本
- `ai-config/global-instructions.md`: 配布用グローバル指示（任意）

## 実行場所のルール

- `init`, `lock-base`, `reset-user`: `setupScript` フォルダで実行
- `*-here`（`sync-here`, `promote-here`, `reset-here`, `all-here`, `status-here`）: PJ フォルダで実行
- `sync`, `promote`, `reset`, `status`, `check`, `diff`, `update`: どこからでも実行可

## Skills の扱い

- 管理対象 skill は `ai-config/skills/` を正本として `sync` / `promote` / `reset` で配布
- 配布先:
  - `~/.claude/skills/`
  - `~/.gemini/skills/`
  - `~/.codex/skills/`
- PJ で作成した skill をユーザ設定へ反映するには `skill-promote` を使う

## ユーザ設定の復旧

```bash
# 完全削除（空状態へ）
./update-ai-clis.sh wipe-user

# Git 管理状態へ復元（setupScript 内で実行）
cd <myCLI_setteing_root>
./update-ai-clis.sh reset-user
```

## ドキュメント

- 最短導入: `START_HERE.md`
- コマンド詳細: `USAGE.md`
- 運用例: `USE_CASES.md`
- レイヤー定義: `ai-config/README.md`

## テスト

```bash
./tests/smoke.sh
./tests/full-smoke.sh
```
