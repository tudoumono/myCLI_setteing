---
name: skill-discovery
description: ナレッジ更新フローの起点として作業完了時に実行する。再利用パターンを kb-candidate と skill-candidate で提案し、承認後に sync-knowledge へ接続する
user-invocable: true
---

# Skill Discovery

作業ログから「再利用価値のあるパターン」を検知し、スキル化候補として提案するためのスキルです。

## 目的

- 学びの検知を人間依存から減らす
- `kb-*` と `skill` を異なる審査強度で運用する
- 既存の更新フロー（`sync-knowledge` / `kb-project-authoring`）へ安全に接続する
- 提案ノイズを抑える

## 実行タイミング

- 作業完了時（最終報告の直前）
- ユーザーが「スキル化できる学びがあるか」を確認したいとき

## 連携フロー（マスター）

```text
実装完了
  → skill-discovery（候補検知）
    → kb-candidate 承認 → sync-knowledge（KB追記）
    → skill-candidate 承認 → sync-knowledge（スキル草案作成）
  → sync-settings（GitHub同期）
```

## ガードレール

1. 作業途中で割り込まない。候補提案は最後に行う。
2. 1セッション（`/clear` まで）で提案上限は `kb-candidate` 1件 + `skill-candidate` 1件（合計最大2件）。
3. 低信頼（根拠が弱い）なら提案しない。
4. ユーザー承認なしで `kb-*` を更新しない。
5. `skill-candidate` は承認されても即反映しない。承認は「草案作成許可」として扱う。
6. CLI固有のスラッシュコマンドに依存しない。

## 検知基準（高信頼の目安）

以下のうち2つ以上を満たす場合のみ候補化する:

- 同種の手順・修正を同一セッションで複数回実施した
- 問題の原因と解決手順が明確に再現可能
- プロジェクト固有ではなく、別PJでも再利用可能
- 手順化すると工数削減が見込める（調査・修正・検証の型がある）

補足:
- コンパクションで「同一セッション内の複数回実施」が判定しづらい場合は、他の基準を優先して判断する。

## 振り分け基準

- 「事実・手順・知見」の追記が主目的: `kb-candidate`（既存 `kb-*` へ追加）
- 「繰り返す作業フロー」の定義が主目的: `skill-candidate`（新規または既存スキル改善）
- 迷う場合は `kb-candidate` を優先する

## 実行手順

1. **候補抽出**
   - 今回の作業から再利用可能なパターンを最大3件抽出
   - 各候補に「症状/原因/手順/検証」を1行ずつメモ

2. **重複チェック**
   - `kb-candidate` は `/root/.claude/skills/kb-*/SKILL.md` を確認し、同等内容が既にないか確認
   - `skill-candidate` は `/root/.claude/skills/*/SKILL.md` を確認し、同等フローの既存スキルがないか確認
   - 同等内容がある候補は破棄

3. **候補の絞り込みとレート制限**
   - `kb-candidate` は最大1件、`skill-candidate` は最大1件まで選ぶ
   - 候補名は英小文字kebab-caseで命名

4. **提案（1行）**
   - `kb-candidate`:
     - `[kb-candidate] <name> | target: <existing kb-*> | reason: <再利用根拠>`
   - `skill-candidate`:
     - `[skill-candidate] <name> | target: <new-skill or existing skill refinement> | reason: <再利用根拠>`

5. **承認後の処理**
   - `kb-candidate` / `skill-candidate` いずれも:
     - `/root/.claude/skills/sync-knowledge/SKILL.md` の手順に従う
     - 振り分けテーブルに従って正しいKBに追記または新規作成
     - `skill-candidate` の場合はまず草案を提示し、最終反映前に再承認を取る

6. **却下時の処理**
   - 却下された場合は何もしない
   - 同一セッション内では同じ候補を再提案しない
   - 永続的な却下履歴（`rejected.yml` 等）は現時点では扱わない（必要になった時点で導入）

## 提案しないケース

- 一回限りの運用作業
- 環境固有・アカウント固有の内容
- 既存 `kb-*` に同等の手順が明記済み

## 次のステップ

候補が承認されたら、`sync-knowledge` を実行してKB追記またはスキル草案作成へ進んでください。
