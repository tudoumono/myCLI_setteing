# ai-config

Layered configuration for Claude/Codex/Gemini baseline.
Main baseline (`base.json`) is intentionally locked.

## Files

- `base.json`: Global baseline (required, locked)
- `base.lock.sha256`: Lock hash for `base.json`
- `projects/<name>.json`: Project overlay (optional)
- `local.json`: Machine-local overlay (optional, do not commit)
- `.ai-stack.local.json`: Folder-local overlay (optional, do not commit)

## Skills

- `skills/<name>/SKILL.md`: Shared skills master (synced to all CLIs)
- Synced destinations:
  - `~/.claude/skills/<name>/SKILL.md`
  - `~/.gemini/skills/<name>/SKILL.md`
  - `~/.codex/skills/<name>/SKILL.md`

## Global Instructions

Layered and concatenated in order:

1. `global-instructions.md` (base, optional)
2. `projects/<name>.instructions.md` (project, optional)
3. `global-instructions.local.md` (machine-local, optional, do not commit)

Distributed files when merged content exists:

- `~/.claude/CLAUDE.md`
- `~/.codex/AGENTS.md`
- `~/.gemini/GEMINI.md`

## Priority

`base.json` < `projects/<name>.json` < `local.json` < `.ai-stack.local.json`

## Policy

- Keep `base.json` stable and minimal.
- Add extra features in `projects/<name>.json`.
- Keep secrets/path overrides in `local.json` or `.ai-stack.local.json`.
- If `base.json` changes, `sync/reset/status` will stop until lock is refreshed.

## Recommended workflow

1. `./update-ai-clis.sh init`
2. Add project-specific differences in `projects/<name>.json`
3. Run `./update-ai-clis.sh sync <name>`
4. Run `./update-ai-clis.sh check` to verify no drift for skills/global-instructions.

If you intentionally update `base.json`, run:

`./update-ai-clis.sh lock-base`
