# フォルダ配置・採番ルール

このスキルは `/root/mywork/note` 配下の次の2系統を対象にする。

- `一般資料/`: プロジェクト固有前提を外した整理資料
- `PJ特化ノート/`: プロジェクト固有の検討メモ・素材整理・議論ログ

## 役割の違い

### `一般資料`

- 一般化できる知識をまとめる。
- 比較表、設計指針、実装パターン、技術解説を置く。
- 他案件で再利用できる粒度にする。

### `PJ特化ノート`

- PJ固有の前提、検討経緯、ユーザー提供素材、暫定案を残す。
- ユーザーの発想起点を保持する。
- 実装前のたたき台や論点整理を許容する。

## 採番ルール（現行）

### `一般資料/`

- `01-09`: 基礎・設計・ツール比較
- `10-19`: RAG・検索・チャンキング
- `20-29`: KB設計・運用（将来拡張）
- `90-99`: 補助資料・索引（将来拡張）
- 命名形式: `NN_タイトル.md`
- `scripts/create_note.py` のカテゴリ補助（例）
  - `--category dify` / `foundation` -> `01-09`
  - `--category rag` / `chunking` -> `10-19`
  - `--category kb` / `operations` -> `20-29`
  - `--category support` / `index` -> `90-99`

### `PJ特化ノート/`

- `01-09`: 入力素材・OCR・原票整理
- `10-19`: 検討メモ・設計たたき台
- `20-29`: 実装メモ・検証ログ
- サブフォルダ内も `NN_` 採番を使う。
- `README.md` は採番しない。
- `scripts/create_note.py` のカテゴリ補助（例）
  - `--category input` / `ocr` / `source` -> `01-09`
  - `--category memo` / `design` -> `10-19`
  - `--category implementation` / `validation` -> `20-29`

## スクリプトで番号帯を守る方法

### 方式1: `--range` を直接指定（推奨）

```bash
python3 scripts/create_note.py --root /root/mywork/note --mode general --range 10-19 --title "RAG再ランキング比較"
```

- 指定した範囲内の空き番号を先頭から使う。
- 範囲が埋まっている場合はエラーにする。

### 方式2: `--category` を指定

```bash
python3 scripts/create_note.py --root /root/mywork/note --mode general --category rag --title "RAG再ランキング比較"
python3 scripts/create_note.py --root /root/mywork/note --mode project --category memo --title "PoC検討メモ"
```

- `--category` はモードごとの番号帯に解決される。
- `--range` と `--category` は同時指定しない。

## 配置判断フロー（簡易）

1. PJ固有前提が消えると意味が落ちるか確認する。
2. 落ちるなら `PJ特化ノート` に置く。
3. 落ちないなら `一般資料` に置く。
4. 両方に価値があるなら、`PJ特化ノート` を元にして後で一般化版を `一般資料` に作る。

## README更新の扱い

- 既存の手書き構成を優先する。
- 自動更新は管理ブロック（`AUTO-INDEX` コメント）だけを更新する。
- 手書きの説明文やおすすめ順は消さない。
