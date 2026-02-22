---
name: research-note-authoring
description: 一般論の調査資料（`一般資料`）とプロジェクト固有の検討メモ（`PJ特化ノート`）を、AIとの議論結果を含めて構造化Markdownとして作成・更新するスキル。必要に応じて Mermaid 図で構造・処理フロー・判断分岐を可視化する。Use when Codex needs to classify notes into general/project, research up-to-date official docs, synthesize discussion points, create numbered note files, add optional Mermaid diagrams, and maintain README indexes under `/root/mywork/note`.
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

### Mermaid 図（任意）

- 図があると理解が速くなる場合のみ ` ```mermaid ` ブロックを追加する。
- 本文（結論・前提・判断理由）を先に書き、図は補助として使う。図だけで結論を表現しない。
- 1ノートあたり 1〜2 図を目安にし、過剰に増やさない。
- 図を入れる候補:
  - 処理フロー（RAG検索、レビュー手順、PoC段階構成）
  - 判断分岐（選定ロジック、採用判断の条件）
  - 構成関係（システム/コンポーネントの関係）
- `general` では一般化した図にする（PJ固有名を減らす）。
- `project` では暫定案であることを明記し、未確定部分は図中または直下に `要確認` を書く。
- Mermaid を表示できない環境もあるため、図の直前または直後に 1〜3 行で要点を文章化する。

## README Index Maintenance

`README.md` の既存の手書き構成を壊さないことを優先する。
自動更新スクリプトは `<!-- AUTO-INDEX:START -->` / `<!-- AUTO-INDEX:END -->` の管理ブロックだけを更新する。

README に管理ブロックがない場合:

1. 手動で既存構成を維持したまま追記する。
2. またはスクリプトで末尾に管理ブロックを追加する。

## Tier 1（手動フォールバック）

Python やスクリプトが使えない環境でも、このスキルは手動で運用できる。
スクリプトは高速化・ミス削減のための補助として扱い、止まった場合でも作業を継続する。

### 手動で完了する最小手順（依存なし）

1. `Mode Selection` を使って `general` / `project` を判断する。
2. 対象フォルダ（`一般資料` / `PJ特化ノート`）の既存ファイル名を見て、次番号または番号帯の空きを決める。
3. `assets/templates/general-note.md` または `assets/templates/project-note.md` をコピーして新規Markdownを作成する。
4. タイトル、目的、結論、論点、参考リンクを埋める。
5. `README.md` に索引を手動で追記する（既存の手書き構成を壊さない）。
6. 上部の README 戻りリンクと相対リンクを目視で確認する。
7. `references/quality-checklist.md` を見て最終確認する。

### 手動運用時の注意

- 番号帯を守る（例: RAG系は `10-19`）。
- PJ特化ノートではユーザー起点の発想を `ユーザー発言/考え/思考` として残す。
- 最新性が重要な技術情報は、確認日と参考リンクを明記する。

### Tier 2（推奨・自動化あり）

Python が使える環境では `scripts/create_note.py` / `scripts/update_readme_index.py` / `scripts/validate_note_links.py` を使って、採番・索引更新・リンク検査を自動化する。

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
Mermaid 図を入れた場合は、本文と矛盾していないか・図だけにしか重要情報が書かれていない状態になっていないかを確認する。
