---
name: ai-stack-assistant
description: AI CLI設定を自然言語で操作。update-ai-clis.shの全コマンドをAI対話で安全に実行
user-invocable: true
argument-hint: "[コマンド or 操作の説明]"
---

# AI Stack Assistant

`update-ai-clis.sh` の全コマンドを自然言語またはコマンド名で安全に実行するスキルです。

**スクリプトパス:** `/root/mywork/setupScript/update-ai-clis.sh`

## コマンド一覧

| カテゴリ | コマンド | 説明 | Tier | dry-run | 引数 |
|---------|---------|------|------|---------|------|
| 初期化 | `init` | ai-config/配下のベースファイルを作成 | 2 | — | なし |
| 初期化 | `lock-base` | base.jsonのハッシュロックを更新 | 2 | — | なし |
| 初期化 | `project-init` | プロジェクト用オーバーレイを初期化しsyncを実行 | 2 | — | [project_dir] |
| 更新 | `update` | Claude/Gemini/Codex CLIをnpm経由で更新 | 2 | 可 | なし |
| 同期 | `sync` | 統合設定を適用（Global+Project+Folderレイヤー） | 2 | 可 | [project] |
| 同期 | `sync-here` | 現在ディレクトリをprojectとしてsync | 2 | 可 | なし |
| リセット | `reset` | ベース状態へ戻す（MCP設定クリア+パッケージ削除） | 3 | 可 | [project] |
| リセット | `reset-here` | 現在ディレクトリをprojectとしてreset | 3 | 可 | なし |
| 一括 | `all` | update → sync を順に実行 | 3 | 可 | [project] |
| 一括 | `all-here` | 現在ディレクトリをprojectとしてall | 3 | 可 | なし |
| 検査 | `diff` | sync実行時の変更を実ファイル変更なしで表示 | 1 | — | [project] |
| 検査 | `check` | skills/global instructionsのドリフト検査 | 1 | — | [project] |
| 検査 | `status` | バージョン情報と有効設定状態を表示 | 1 | — | [project] |
| 検査 | `status-here` | 現在ディレクトリをprojectとしてstatus | 1 | — | なし |
| スキル | `skill-share` | 指定ローカルスキルを3CLI間で共有 | 2 | 可 | \<skill_name\> |
| スキル | `skill-share-all` | ローカルスキル全てを3CLI間で一括共有 | 3 | 可 | なし |

## 安全ルール（必須遵守）

### Tier 1: 読み取り専用 → 即実行OK

`status`, `status-here`, `diff`, `check` は情報表示のみ。確認なしで実行してよい。

### Tier 2: 書き込み → dry-run先行

`sync`, `sync-here`, `update`, `init`, `lock-base`, `project-init`, `skill-share` は設定ファイルを変更する。

1. まず `--dry-run` を付けて実行し、変更内容をユーザーに提示する
2. ユーザーが確認したら本実行する
3. `--dry-run` 非対応のコマンド（`init`, `lock-base`, `project-init`）は実行内容を説明してから確認を取る

### Tier 3: 破壊的 → dry-run + 明示確認必須

`reset`, `reset-here`, `all`, `all-here`, `skill-share-all` は既存設定を上書き・削除する。

1. `--dry-run` を付けて実行し、影響範囲をユーザーに提示する
2. 「この操作は既存設定を上書き/削除します。実行してよいですか？」と明示的に確認する
3. ユーザーの明確な承認（「はい」「OK」「やって」等）があった場合のみ本実行する

### 実行場所の制約

- `init`, `lock-base` は setupScript フォルダでのみ実行可能
- `*-here` コマンド（`sync-here`, `reset-here`, `all-here`, `status-here`）は setupScript 以外のプロジェクトフォルダで実行する

### 禁止事項

- `ai-config/base.json` を直接編集しない（`lock-base` でロック管理されている）
- ユーザー確認なしで Tier 3 コマンドを実行しない
- `--dry-run` の結果を省略・要約せず、そのまま表示する

## $ARGUMENTS 処理

### コマンド名が直接指定された場合

`$ARGUMENTS` が既知のコマンド名（`status`, `sync`, `reset` 等）またはコマンド名+引数の場合、そのコマンドを Tier に応じた安全手順で実行する。

### 自然言語で指定された場合

`$ARGUMENTS` がコマンド名でない場合、自然言語マッピングを参照して対応するコマンドを特定し、ユーザーに確認してから実行する。

### 空の場合

以下のように聞く：

> 何をしますか？よく使う操作:
> - **設定の状態確認** → `status`
> - **設定の同期** → `sync` / `sync-here`
> - **変更のプレビュー** → `diff`
> - **CLIの更新** → `update`
> - **ドリフト検査** → `check`
>
> 操作を教えてください（コマンド名でも自然言語でもOK）。

## 自然言語マッピング

| ユーザーの言い方 | コマンド |
|-----------------|---------|
| 設定を見せて / 今の状態は / バージョン確認 | `status` |
| 設定を同期して / 反映して / 適用して | `sync` or `sync-here` |
| 何が変わるか見せて / プレビュー / 差分 | `diff` |
| CLIを更新して / アップデート | `update` |
| 全部やって / 更新して同期 | `all` or `all-here` |
| 初期化して / セットアップ | `init` or `project-init` |
| リセットして / 元に戻して / 初期状態に | `reset` or `reset-here` |
| ドリフトチェック / 整合性確認 | `check` |
| スキルを共有して / スキル配布 | `skill-share` or `skill-share-all` |
| ロックを更新 / ベース更新を確定 | `lock-base` |

コンテキストから `-here` 変種を使うべきか判断する:
- 現在のディレクトリが setupScript 以外のプロジェクトなら `-here` を使う
- プロジェクト名が指定されていれば通常版を使う

## よくあるワークフロー

### 初回セットアップ

```
1. init          — ベースファイル作成（setupScriptで実行）
2. sync          — 設定を3CLIに配布
3. status        — 配布結果を確認
```

### プロジェクト追加

```
1. project-init <dir>  — プロジェクトオーバーレイ作成 + sync
2. status <project>    — 結果確認
```

### 日常の設定同期

```
1. diff [project]      — 変更のプレビュー
2. sync [project]      — 設定を適用
3. check [project]     — ドリフトがないことを確認
```

### 設定のリカバリ

```
1. status [project]    — 現在の状態を確認
2. reset [project]     — ベース状態に戻す
3. sync [project]      — 設定を再適用
```

## エラー対応

| エラー | 原因 | 対処 |
|-------|------|------|
| `node is required but not found` | Node.js未インストール | `nvm install --lts` を案内 |
| `base.json not found` | init未実行 | `init` コマンドを実行 |
| `base.json hash mismatch` | base.jsonが手動編集された | 意図した変更なら `lock-base`、意図しない変更なら `git checkout` |
| `Cannot run *-here from setupScript` | setupScriptフォルダで-hereを実行 | プロジェクトフォルダへ移動するか通常版を使う |
| `Skill is managed` (skill-share) | managed skillをshareしようとした | managed skillは `sync` で配布される |
| `npm ERR!` (update) | ネットワークまたは権限の問題 | ネットワーク確認、`sudo` が必要か確認 |

## コマンド実行テンプレート

### 実行前チェックリスト

1. コマンドの Tier を確認する
2. Tier 2/3 なら dry-run 可否を確認する
3. 引数（project名、skill名など）が必要か確認する
4. 実行場所の制約を確認する（`init` → setupScript、`*-here` → setupScript以外）

### 実行方法

```bash
# Tier 1（即実行OK）
/root/mywork/setupScript/update-ai-clis.sh status

# Tier 2（dry-run → 確認 → 本実行）
/root/mywork/setupScript/update-ai-clis.sh sync --dry-run
# → 結果を提示、確認後:
/root/mywork/setupScript/update-ai-clis.sh sync

# Tier 3（dry-run → 明示確認 → 本実行）
/root/mywork/setupScript/update-ai-clis.sh reset --dry-run
# → 影響範囲を提示、明確な承認後:
/root/mywork/setupScript/update-ai-clis.sh reset
```

### 出力の報告ルール

- コマンド出力はコードブロックでそのまま表示する
- エラーが発生した場合はエラー対応テーブルを参照して対処法も提示する
- 成功時は次に推奨される操作を提案する（例: sync後 → `check` でドリフト検査）
