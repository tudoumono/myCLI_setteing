---
name: sync-settings
description: Claude/Codex/Gemini 向け共通設定を GitHub 正本へ同期する。skills、agents、CLAUDE.md、mcpServers、settings一部の Push/Pull に使う
user-invocable: true
---

# GitHub設定同期

Claude Codeの**共通設定のみ**をGitHubリポジトリと双方向同期します。

## 同期対象（共通設定）

| ローカル | リポジトリ | 備考 |
|----------|------------|------|
| `~/.claude/skills/` | `claude/skills/` | ナレッジベース含む |
| `~/.claude/agents/` | `claude/agents/` | カスタムエージェント |
| `~/.claude/CLAUDE.md` | `claude/CLAUDE.md` | |
| `~/.claude.json` の `mcpServers` | `.claude.json` | 機密情報はマスク |
| `~/.claude/settings.json` の一部 | `claude/settings.json` | spinnerVerbs, language のみ |

## mcpServers同期の注意事項

`mcpServers`セクションは以下のルールで同期：

1. **Push時**: 環境変数の値（トークン等）を `"<MASKED>"` に置換してエクスポート
2. **Pull時**: リポジトリのJSONを参考に手動で設定（機密情報は各自で設定）

### 機密情報のマスク対象

以下のキーの値は自動的にマスクされる：
- `GITHUB_PERSONAL_ACCESS_TOKEN`
- `*_API_KEY`
- `*_TOKEN`
- `*_SECRET`

## 同期対象外（PC固有設定）

以下はPC固有のため**同期しない**：

- `~/.claude/settings.json` の一部 - permissions、hooks、statusLine（PC固有パスやOS依存）
- `~/.claude/hooks/` - フックスクリプト
- `~/.claude/projects/` - プロジェクト固有設定
- `~/.claude/plugins/` - プラグイン設定
- `~/.claude/rules/` - **廃止済み（skillsに移行）**
- その他キャッシュ、履歴、デバッグログ等

## 同期先リポジトリ（固定）

同期先は以下のGitHubリポジトリに固定する：

`https://github.com/tudoumono/myCLI_setteing`

実行時は、ローカルclone先を `REPO_DIR` として扱う：

```bash
REPO_URL="https://github.com/tudoumono/myCLI_setteing"
REPO_DIR="${HOME}/git/myCLI_setteing"

if [ ! -d "${REPO_DIR}/.git" ]; then
  git clone "${REPO_URL}" "${REPO_DIR}"
fi
```

## 実行手順

### Push（ローカル → リポジトリ）

1. **差分確認**
   ```bash
   diff -rq ~/.claude/skills/ "${REPO_DIR}/claude/skills/"
   diff -rq ~/.claude/agents/ "${REPO_DIR}/claude/agents/"
   diff ~/.claude/CLAUDE.md "${REPO_DIR}/claude/CLAUDE.md"
   diff <(jq '{spinnerVerbs, language}' ~/.claude/settings.json) <(jq '{spinnerVerbs, language}' "${REPO_DIR}/claude/settings.json" 2>/dev/null || echo '{}')
   ```

2. **同期実行**
   ```bash
   rsync -av --delete ~/.claude/skills/ "${REPO_DIR}/claude/skills/"
   rsync -av --delete ~/.claude/agents/ "${REPO_DIR}/claude/agents/"
   cp ~/.claude/CLAUDE.md "${REPO_DIR}/claude/"
   ```

3. **settings.json同期**（spinnerVerbs, languageのみ）
   ```bash
   jq -s '.[0] * {spinnerVerbs: .[1].spinnerVerbs, language: .[1].language}' \
     "${REPO_DIR}/claude/settings.json" \
     ~/.claude/settings.json > /tmp/settings.json && \
   mv /tmp/settings.json "${REPO_DIR}/claude/settings.json"
   ```

4. **mcpServers同期**（機密情報をマスクしてエクスポート）
   ```bash
   jq '{mcpServers: .mcpServers | walk(
     if type == "object" then
       with_entries(
         if (.key | test("TOKEN|KEY|SECRET"; "i")) and (.value | type == "string")
         then .value = "<MASKED>"
         else .
         end
       )
     else .
     end
   )}' ~/.claude.json > "${REPO_DIR}/.claude.json"
   ```

5. **コミット・プッシュ**（ユーザー確認後）
   ```bash
   cd "${REPO_DIR}"
   git add -A
   git status
   git commit -m "設定同期"
   git push
   ```

### Pull（リポジトリ → ローカル）

1. **リポジトリを最新化**
   ```bash
   cd "${REPO_DIR}"
   git pull
   ```

2. **差分確認**
   ```bash
   diff -rq "${REPO_DIR}/claude/skills/" ~/.claude/skills/
   diff -rq "${REPO_DIR}/claude/agents/" ~/.claude/agents/
   diff "${REPO_DIR}/claude/CLAUDE.md" ~/.claude/CLAUDE.md
   ```

3. **同期実行**（ユーザー確認後）
   ```bash
   rsync -av --delete "${REPO_DIR}/claude/skills/" ~/.claude/skills/
   rsync -av --delete "${REPO_DIR}/claude/agents/" ~/.claude/agents/
   cp "${REPO_DIR}/claude/CLAUDE.md" ~/.claude/
   ```

4. **settings.json適用**（spinnerVerbs, languageのみ）
   ```bash
   jq -s '.[0] * {spinnerVerbs: .[1].spinnerVerbs, language: .[1].language}' \
     ~/.claude/settings.json \
     "${REPO_DIR}/claude/settings.json" > /tmp/settings.json && \
   mv /tmp/settings.json ~/.claude/settings.json
   ```

5. **mcpServers適用**（手動）
   - `.claude.json` を参照して `~/.claude.json` の `mcpServers` を更新
   - `<MASKED>` 部分は各自の認証情報に置き換える

## 注意事項

- 機密情報（APIキー等）が含まれていないか確認
- 新しいPCでPullする前に、既存のローカル設定をバックアップ推奨
- プッシュ前に必ずユーザーに確認を取る
