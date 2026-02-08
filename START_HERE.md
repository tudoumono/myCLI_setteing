# START HERE

このドキュメントは、`setupScript` を初めて使う人向けの最短ガイドです。

## まず理解すること

- Git 管理の正本は `ai-config/*`。
- PJ 固有の設定は PJ フォルダに置く。
- PJ の設定を `~/.claude` / `~/.codex` / `~/.gemini` に反映する時は `promote*` を使う。
- `sync-here` は確認用（プレビュー）で、反映はしない。

## 5分セットアップ

1. リポジトリを手動 clone（`myCLI_setteing`）
2. `setupScript` で初期化

```bash
cd /path/to/myCLI_setteing
./update-ai-clis.sh init
./update-ai-clis.sh status
```

3. 必要ならドリフト確認

```bash
./update-ai-clis.sh check
```

## PJ開始の基本フロー

```bash
# PJ管理ファイルを作成
/path/to/myCLI_setteing/update-ai-clis.sh project-init /path/to/my-project

# PJ側で確認（まだ反映しない）
cd /path/to/my-project
/path/to/myCLI_setteing/update-ai-clis.sh sync-here

# 反映したい時だけ昇格
/path/to/myCLI_setteing/update-ai-clis.sh promote-here

# 状態確認
/path/to/myCLI_setteing/update-ai-clis.sh status-here
```

`project-init` で作成されるもの:
- `<project>/.ai-stack.local.json`
- `<project>/BACKLOG.md`

## よく使う判断

- 差分だけ見たい: `sync-here` または `diff`
- PJ内容を実際に反映したい: `promote-here`
- ユーザ設定を完全に空にしたい: `wipe-user`
- Git 管理状態へ戻したい: `reset-user`

## よくある誤解

- `sync-here` は反映コマンドではありません（プレビュー専用）。
- `project-init` は `~/` 配下を直接書き換えません。
- `base.json` は最優先ではなく下位レイヤーの共通ベースです。

## メニューで使う場合

```bash
./menu.sh
```

- `whiptail` があればダイアログ UI、なければテキスト UI。
- 日常運用は `sync-here -> promote-here -> status-here` の順で使うと安全です。

## 次に読む

- 詳細コマンド: `USAGE.md`
- 運用例: `USE_CASES.md`
- 全体方針: `README.md`
