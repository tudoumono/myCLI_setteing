# ユースケース集

このドキュメントは、`setupScript` の日常運用を「何をするときに何を実行するか」で整理した実践ガイドです。

## 前提（重要）

- 正本（マスター）: `setupScript/ai-config/`
- 配布先（ランタイム）: `~/.claude/`, `~/.codex/`, `~/.gemini/`

このプロジェクトは「`init` で正本を用意し、日常はPJ整合性を保つ」運用です。  
`sync/reset/status/check` など通常コマンドは、正本不足時に自動作成しません（エラー終了）。

補足:
- `ai-config/base.json` は共通ベース（下位レイヤー）です。最優先設定ではありません。
- PJで良かった内容を全体へ反映する場合、昇格は手動です（専用の `promote` コマンドはありません）。

## 1. 初回セットアップ（このPCで最初の1回）

```bash
cd /root/mywork/setupScript
./update-ai-clis.sh init
./update-ai-clis.sh sync
./update-ai-clis.sh status
```

## 2. 新しいPJを開始する

```bash
cd /path/to/my-project
/root/mywork/setupScript/update-ai-clis.sh project-init
/root/mywork/setupScript/update-ai-clis.sh status-here
```

`project-init` は `.ai-stack.local.json` と `BACKLOG.md` を作成し、初回同期まで行います。

## 3. 日常運用（推奨）

```bash
# PJフォルダで
/root/mywork/setupScript/update-ai-clis.sh sync-here
/root/mywork/setupScript/update-ai-clis.sh status-here
```

変更前確認が必要なら:

```bash
/root/mywork/setupScript/update-ai-clis.sh diff
/root/mywork/setupScript/update-ai-clis.sh sync-here --dry-run
```

## 4. 復旧したいとき

```bash
/root/mywork/setupScript/update-ai-clis.sh reset-here --dry-run
/root/mywork/setupScript/update-ai-clis.sh reset-here
```

## 5. PJ固有スキルを3CLIで使い回す（正本に入れない）

```bash
# 1件共有
/root/mywork/setupScript/update-ai-clis.sh skill-share my-project-skill

# ローカルスキル一括共有
/root/mywork/setupScript/update-ai-clis.sh skill-share-all
```

補足:
- `ai-config/skills` にある managed skill は `skill-share` 対象外です（`sync` で配布）。

## 6. PJで作った設定/スキルを全体標準へ昇格する

全PJに効かせたい内容は、PJローカルのままにせず正本へ反映します。

1. 設定を正本へ移す  
- 全体共通: `ai-config/base.json`  
- PJ単位: `ai-config/projects/<project>.json`

2. スキルを正本へ移す  
- `ai-config/skills/<skill_name>/SKILL.md`

3. `base.json` を更新した場合のみロック更新  

```bash
cd /root/mywork/setupScript
./update-ai-clis.sh lock-base
```

4. 全CLIへ配布  

```bash
./update-ai-clis.sh sync
```

## 7. Gitで他メンバーと共有する

共有できるのは「正本（`ai-config/*`）」です。  
各メンバーの `~/.claude` / `~/.codex` / `~/.gemini` はローカル実体なので、pull後に反映が必要です。

```bash
# 変更を共有する側
git add ai-config README.md USAGE.md START_HERE.md USE_CASES.md
git commit -m "Update master config"
git push
```

```bash
# 受け取る側
git pull
cd /root/mywork/setupScript
./update-ai-clis.sh init   # 初回のみ
./update-ai-clis.sh sync
```

## 8. 正本不足のチェック

日常コマンドで検出できます（不足時はエラー終了）。

```bash
cd /root/mywork/setupScript
./update-ai-clis.sh status
# または
./update-ai-clis.sh sync --dry-run
```

個別確認する場合:

```bash
cd /root/mywork/setupScript
for p in \
  ai-config/base.json \
  ai-config/base.lock.sha256 \
  ai-config/codex-base.toml \
  ai-config/projects \
  ai-config/skills
do
  [[ -e "$p" ]] || echo "MISSING: $p"
done
```

## 9. 正本不足の修復

```bash
cd /root/mywork/setupScript
./update-ai-clis.sh init
```

`base.json` を意図的に編集した場合のみ、続けて:

```bash
./update-ai-clis.sh lock-base
```

意図しない変更なら Git から戻してから実行してください。
