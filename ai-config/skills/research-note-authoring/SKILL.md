---
name: research-note-authoring
description: 一般論の調査資料（`一般資料`）とプロジェクト固有の検討メモ（`PJ特化ノート`）を、AIとの議論結果を含めて構造化Markdownとして作成・更新するスキル。Use when Codex needs to classify notes into general/project, research up-to-date official docs, synthesize discussion points, create numbered note files, and maintain README indexes under `/root/mywork/note`.
---

# Research Note Authoring

## Overview

`/root/mywork/note` 配下のノート作成・更新を標準化する。
`一般資料` と `PJ特化ノート` の振り分け、既存ノート調査、Markdown作成、README索引更新、リンク検証まで一貫して行う。

## Workflow

1. 依頼内容を `general`（一般化できる）/ `project`（PJ前提が重要）に分類する。
2. 既存ノートを検索して重複・関連ノート・追記先候補を確認する。
3. 必要な調査を行う。最新情報が関わる場合は公式ドキュメント/一次情報を優先して確認する。
4. 先に結論を置く構成で、テンプレートに沿って Markdown を作成・更新する。
5. `README.md` の索引を更新する（手動または `scripts/update_readme_index.py`）。
6. リンク・出典・分類ルールを検証する。

## Mode Selection

### `general` を選ぶ基準

- プロジェクト固有前提を外しても価値が残る。
- 他案件でも再利用できる比較・設計指針・実装パターンが中心。
- 例: 技術比較、RAG戦略、ツール使い分け、設計の一般論。

### `project` を選ぶ基準

- ユーザー提供素材やPJ固有前提が重要。
- 誰の発想か（ユーザー起点/AI整理）を保持する必要がある。
- 例: 検討メモ、たたき台、意思決定ログ、OCR起点の整理。

迷う場合は `project` で作成し、後で一般化できる内容を `general` に再構成する。

## File Placement Rules

基本ルールは `references/folder-rules.md` を読む。
PJ特化の出典表記は `references/source-policy.md` を読む。

既定の配置先:

- `general` -> `/root/mywork/note/一般資料`
- `project` -> `/root/mywork/note/PJ特化ノート`

サブフォルダ（例: `PJ特化ノート/ユースケース分類`）を使う場合は、親フォルダのルールを優先する。

## Research Rules

最新性が重要なテーマ（AWS、LLM、Dify、RAG実装、ライブラリ仕様、料金、モデルIDなど）は必ず確認する。
調査ポリシーは `references/research-policy.md` を読む。

最低限守ること:

- 公式ドキュメント/一次情報を優先する。
- 日付が重要な情報はノート内に確認日を書く。
- 事実と推測を分ける。
- 参考リンクを残す。

## Authoring Rules

### 共通ルール

- 読み手が初心者でも追えるように「目的 -> 前提 -> 結論 -> 詳細」の順で書く。
- 長文は目次を付ける。
- 「先に結論」を置く。
- 用語の比較や選択肢がある場合は表を使う。
- 未確定事項は `未決事項` や `要確認` として明示する。

### `general` ノート

- `assets/templates/general-note.md` をベースにする。
- プロジェクト固有語を減らして一般化する。
- 実務での使い方、注意点、選び方を含める。

### `project` ノート

- `assets/templates/project-note.md` をベースにする。
- ユーザー起点の発想を埋もれさせない。
- 出典表記（`ユーザー発言/考え/思考`）を必要箇所に残す。
- 暫定結論と次アクションを分けて書く。

## README Index Maintenance

`README.md` の既存の手書き構成を壊さないことを優先する。
自動更新スクリプトは `<!-- AUTO-INDEX:START -->` / `<!-- AUTO-INDEX:END -->` の管理ブロックだけを更新する。

README に管理ブロックがない場合:

1. 手動で既存構成を維持したまま追記する。
2. またはスクリプトで末尾に管理ブロックを追加する。

## Scripts

### `scripts/create_note.py`

採番付きの新規ノートを作成する。テンプレートを読み込み、見出し・トップREADMEリンク・更新日を埋める。
番号帯を守りたい場合は `--range` または `--category` を使う。

例:

```bash
python3 scripts/create_note.py --root /root/mywork/note --mode general --title "Bedrock AgentCore比較"
python3 scripts/create_note.py --root /root/mywork/note --mode general --category rag --title "再ランキング比較"
python3 scripts/create_note.py --root /root/mywork/note --mode general --range 10-19 --title "RAG評価メモ"
python3 scripts/create_note.py --root /root/mywork/note --mode project --subdir ユースケース分類 --title "PoC進め方メモ"
python3 scripts/create_note.py --root /root/mywork/note --mode project --category memo --title "検討ログ"
```

### `scripts/update_readme_index.py`

README の自動索引ブロックを生成/更新する。

例:

```bash
python3 scripts/update_readme_index.py --root /root/mywork/note --mode general --dry-run
python3 scripts/update_readme_index.py --root /root/mywork/note --mode project
```

### `scripts/validate_note_links.py`

Markdown のローカルリンク切れを検出する。

例:

```bash
python3 scripts/validate_note_links.py /root/mywork/note/一般資料
python3 scripts/validate_note_links.py /root/mywork/note/PJ特化ノート
```

## References To Load On Demand

- `references/folder-rules.md`: フォルダ役割・採番・配置ルール
- `references/research-policy.md`: 調査ポリシー（最新性/一次情報/出典）
- `references/source-policy.md`: PJ特化ノートの出典表記ルール
- `references/quality-checklist.md`: 完了前チェック

## Final Check

完了前に `references/quality-checklist.md` を確認する。
自動生成の結果を過信せず、分類・結論・出典・リンクを最終確認する。
