---
name: kb-project-authoring
description: プロジェクトで得た学びを再利用可能な kb-* スタイルのスキルとして作成・更新する。トラブルシュート記録、実装パターン、アーキテクチャ判断、フレームワーク固有の注意点を整理し、将来の再利用に向けて /root/.codex/skills 配下の構造化された SKILL.md に落とし込む。
---

# Project KB Authoring

Convert project-specific learnings into reusable kb-* style skills.

## Workflow

1. Identify source material.
- Read project docs and notes first: `docs/`, `documents/`, `README.md`, `KNOWLEDGE.md`, runbooks, and recent task outputs.
- Extract concrete facts: symptom, root cause, fix, command, code pattern, and constraints.

2. Separate reusable knowledge from project-only details.
- Keep only knowledge that is likely useful in another project.
- Remove project identifiers, account IDs, resource names, private URLs, and secrets.
- Replace fixed values with placeholders when needed.

3. Select target skill and scope.
- Update existing skill if scope matches (for example `kb-frontend` or `kb-troubleshooting`).
- Create a new `kb-<topic>` skill if scope is new and cohesive.
- Keep one skill focused on one domain.

4. Write in kb-* structure.
- Keep short context section for the domain.
- Add actionable patterns with minimal but executable snippets.
- Add troubleshooting entries in a strict structure:
  - Symptom
  - Cause
  - Fix
  - Verification
- Prefer concise examples and commands over long prose.

5. Apply merge and dedup rules.
- Merge similar items instead of creating duplicates.
- Keep the newest or most reliable pattern when conflicts exist.
- Mark obsolete approaches explicitly as deprecated.

6. Run safety checks before saving.
- Ensure no API keys, tokens, secrets, private endpoints, or personal data remain.
- Ensure commands are environment-safe and include prerequisites.
- Ensure sections are readable and searchable by heading names.

7. Report update summary.
- List which skill was updated or created.
- List added/changed knowledge points.
- List any open validation items that still need real-project verification.

## Output Template

Use this when creating a new `kb-<topic>/SKILL.md`.

```markdown
---
name: kb-<topic>
description: <Domain knowledge summary and clear trigger contexts>
---

# <Topic> Knowledge

## Basic Patterns

### <Pattern Name>
- When to use
- Minimal steps

```bash
# command example
```

## Troubleshooting

### <Issue Name>

**Symptom**: ...

**Cause**: ...

**Fix**:
```bash
# fix command or code
```

**Verification**:
```bash
# verification command
```
```

## Quality Bar

- Keep entries specific enough to execute without guessing.
- Keep entries general enough to reuse in other projects.
- Prefer official docs and observed behavior over assumptions.
