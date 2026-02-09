# ai-config

Claude / Codex / Gemini の設定正本です。

## Files

- `base.json`: 共通ベース（required, locked）
- `base.lock.sha256`: `base.json` ロックハッシュ
- `projects/<name>.json`: 旧来互換のPJオーバーレイ（optional）
- `local.json`: マシンローカルオーバーレイ（optional, usually not committed）
- `skills/<name>/SKILL.md`: 管理対象 skill の正本
- `agents/*.md`: 管理対象 agents の正本
- `global-instructions.md`: 共通指示（optional）
- `global-instructions.local.md`: マシンローカル指示（optional, usually not committed）

Project-side files:

- `<project>/.ai-stack.local.json`: PJローカルオーバーレイ（optional, commit可）
- `<project>/.ai-stack.instructions.md`: PJローカル指示（optional, commit可）
- `<project>/BACKLOG.md`: PJ保留メモ（`project-init` で作成）

## Priority

`base.json` < `projects/<name>.json` < `local.json` < `<project>/.ai-stack.local.json`

## Distribution

Managed skills and instructions are copied to:

- `~/.claude/skills/`, `~/.claude/agents/` and `~/.claude/CLAUDE.md`
- `~/.gemini/skills/`, `~/.gemini/agents/` and `~/.gemini/GEMINI.md`
- `~/.codex/skills/`, `~/.codex/agents/` and `~/.codex/AGENTS.md`

## Operation policy

- Keep `base.json` minimal and stable.
- Prefer project-local settings in `<project>/.ai-stack.local.json`.
- PJ changes are applied to user settings only via `promote` / `promote-here`.
- Initial apply / full restore use `init` / `reset-user`.
- If `base.json` changes intentionally, run `./update-ai-clis.sh lock-base`.
