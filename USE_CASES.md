# ユースケース集

`setupScript` を日常運用でどう使うかを、目的別に整理したガイドです。

## 前提

- 正本: `setupScript/ai-config/`
- ランタイム配布先: `~/.claude/`, `~/.codex/`, `~/.gemini/`
- PJから `~/` へ反映するのは `promote*` のみ（`sync-here` は確認専用）

## 1. 初回セットアップ（このPCで最初の1回）

```bash
cd <myCLI_setteing_root>
./update-ai-clis.sh init
./update-ai-clis.sh status
```

## 2. 新しいPJを開始

```bash
<myCLI_setteing_root>/update-ai-clis.sh project-init /path/to/my-project
cd /path/to/my-project
<myCLI_setteing_root>/update-ai-clis.sh sync-here
```

`project-init` は `.ai-stack.local.json` と `BACKLOG.md` を作り、差分プレビューを表示します。

## 3. PJ設定を実際に反映

```bash
cd /path/to/my-project
<myCLI_setteing_root>/update-ai-clis.sh promote-here
<myCLI_setteing_root>/update-ai-clis.sh status-here
```

## 4. 変更前に影響確認

```bash
<myCLI_setteing_root>/update-ai-clis.sh sync-here --dry-run
<myCLI_setteing_root>/update-ai-clis.sh promote-here --dry-run
<myCLI_setteing_root>/update-ai-clis.sh reset-here --dry-run
```

## 5. PJ固有スキルを3CLIへ昇格

```bash
<myCLI_setteing_root>/update-ai-clis.sh skill-promote /path/to/my-project/my-skill
```

既存スキル名を共有する場合:

```bash
<myCLI_setteing_root>/update-ai-clis.sh skill-share my-project-skill
```

## 6. ユーザ設定を完全初期化/復元

```bash
# まず確認
<myCLI_setteing_root>/update-ai-clis.sh wipe-user --dry-run

# 完全削除
<myCLI_setteing_root>/update-ai-clis.sh wipe-user

# Git管理状態へ復元
cd <myCLI_setteing_root>
./update-ai-clis.sh reset-user
```

## 7. Gitで他メンバーと共有

共有するのは `ai-config/*`（正本）です。`~/.claude` などは各自ローカル実体なので、pull後に反映が必要です。

```bash
# 変更側
git add ai-config README.md START_HERE.md USAGE.md USE_CASES.md
git commit -m "Update ai config docs"
git push
```

```bash
# 受け取り側
git pull
cd <myCLI_setteing_root>
./update-ai-clis.sh reset-user
```

## 8. ドリフト検査

```bash
cd <myCLI_setteing_root>
./update-ai-clis.sh check
```

## 9. 3CLI配布先へ反映（skills含む）

- 正本変更後は `promote` か `reset-user` で反映する。
- PJ文脈での `sync` / `sync-here` は配布反映しないため、配布目的なら使わない。

```bash
cd <myCLI_setteing_root>
./update-ai-clis.sh promote
```
