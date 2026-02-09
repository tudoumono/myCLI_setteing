#!/usr/bin/env bash
# tests/full-smoke.sh — Comprehensive smoke tests for update-ai-clis.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
TMP_HOME="$(mktemp -d)"
TMP_WORK="$(mktemp -d)"
TMP_PROJECT_LOCAL="$(mktemp -d)"
SCRIPT_DIR=""
SCRIPT=""
SETTINGS_BEFORE=""
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

cleanup() {
  rm -rf "${TMP_ROOT}" "${TMP_HOME}" "${TMP_WORK}" "${TMP_PROJECT_LOCAL}"
  if [[ -n "${SETTINGS_BEFORE}" && -f "${SETTINGS_BEFORE}" ]]; then
    rm -f "${SETTINGS_BEFORE}"
  fi
}
trap cleanup EXIT

cp -a "${ROOT_DIR}/." "${TMP_ROOT}/setupScript"
SCRIPT_DIR="${TMP_ROOT}/setupScript"
SCRIPT="${SCRIPT_DIR}/update-ai-clis.sh"
export HOME="${TMP_HOME}"

pass() { PASS=$((PASS + 1)); printf "${GREEN}  PASS${NC} %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "${RED}  FAIL${NC} %s\n" "$1"; }

assert_exit_0() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "${label}"; else fail "${label}"; fi
}

assert_exit_nonzero() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "${label}"; else pass "${label}"; fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "${path}" ]]; then pass "${label}"; else fail "${label}: ${path}"; fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  if [[ ! -f "${path}" ]]; then pass "${label}"; else fail "${label}: ${path} should not exist"; fi
}

assert_file_contains() {
  local label="$1" path="$2" pattern="$3"
  if grep -q "${pattern}" "${path}" 2>/dev/null; then pass "${label}"; else fail "${label}: '${pattern}' not in ${path}"; fi
}

assert_files_equal() {
  local label="$1" a="$2" b="$3"
  if cmp -s "${a}" "${b}"; then pass "${label}"; else fail "${label}: ${a} != ${b}"; fi
}

echo "=== Full Smoke Tests (Sandboxed) ==="
echo ""

# --- init ---
echo "-- init --"
assert_exit_nonzero "init fails outside setupScript dir" bash -lc "cd \"${TMP_WORK}\" && \"${SCRIPT}\" init"
assert_exit_nonzero "lock-base fails outside setupScript dir" bash -lc "cd \"${TMP_WORK}\" && \"${SCRIPT}\" lock-base"
assert_exit_0 "init runs" bash -lc "cd \"${SCRIPT_DIR}\" && \"${SCRIPT}\" init"
assert_file_exists "base.json exists" "${SCRIPT_DIR}/ai-config/base.json"
assert_file_exists "base.lock exists" "${SCRIPT_DIR}/ai-config/base.lock.sha256"
assert_file_exists "codex-base.toml exists" "${SCRIPT_DIR}/ai-config/codex-base.toml"

rm -f "${SCRIPT_DIR}/ai-config/base.lock.sha256"
assert_exit_nonzero "sync fails when base lock missing" "${SCRIPT}" sync
assert_exit_nonzero "all --dry-run fails when base lock missing" "${SCRIPT}" all --dry-run
assert_exit_nonzero "all-here --dry-run fails when base lock missing" bash -lc "cd \"${TMP_WORK}\" && \"${SCRIPT}\" all-here --dry-run"
assert_exit_0 "lock-base restores base lock" bash -lc "cd \"${SCRIPT_DIR}\" && \"${SCRIPT}\" lock-base"
assert_file_exists "base.lock restored" "${SCRIPT_DIR}/ai-config/base.lock.sha256"

# --- project-init ---
echo "-- project-init --"
assert_exit_0 "project-init runs" "${SCRIPT}" project-init "${TMP_PROJECT_LOCAL}"
assert_file_exists "project local config exists" "${TMP_PROJECT_LOCAL}/.ai-stack.local.json"
assert_file_contains "project local config has projectServers" "${TMP_PROJECT_LOCAL}/.ai-stack.local.json" "projectServers"
assert_file_not_exists "project-init does not create .gitignore by default" "${TMP_PROJECT_LOCAL}/.gitignore"
assert_file_not_exists "project-init does not create legacy overlay" "${SCRIPT_DIR}/ai-config/projects/$(basename "${TMP_PROJECT_LOCAL}").json"

# --- promote flow ---
echo "-- promote flow --"
cat > "${TMP_PROJECT_LOCAL}/.ai-stack.local.json" <<'EOF'
{
  "projectServers": ["pj-test-server"],
  "servers": {
    "pj-test-server": {
      "enabled": true,
      "command": "echo",
      "args": ["hello-from-project"],
      "targets": ["claude", "codex", "gemini"],
      "delivery": {
        "claude": "plugin",
        "codex": "config",
        "gemini": "settings"
      }
    }
  }
}
EOF

assert_exit_0 "sync-here runs (preview only)" bash -lc "cd \"${TMP_PROJECT_LOCAL}\" && \"${SCRIPT}\" sync-here"
assert_file_not_contains() {
  local label="$1" path="$2" pattern="$3"
  if ! grep -q "${pattern}" "${path}" 2>/dev/null; then pass "${label}"; else fail "${label}: '${pattern}' unexpectedly in ${path}"; fi
}
assert_file_not_contains "sync-here did not apply project server to codex" "${HOME}/.codex/config.toml" "pj-test-server"

assert_exit_0 "promote-here applies project settings" bash -lc "cd \"${TMP_PROJECT_LOCAL}\" && \"${SCRIPT}\" promote-here"
assert_file_contains "promote-here applied project server to codex" "${HOME}/.codex/config.toml" "pj-test-server"

# --- sync ---
echo "-- sync --"
assert_exit_0 "sync runs" "${SCRIPT}" sync
assert_file_exists "claude.json has mcpServers" "${HOME}/.claude.json"
assert_file_contains "claude settings has WebSearch" "${HOME}/.claude/settings.json" "WebSearch"
assert_file_exists "codex config exists" "${HOME}/.codex/config.toml"
assert_file_contains "codex has managed MCP" "${HOME}/.codex/config.toml" "BEGIN MANAGED MCP"
assert_file_exists "gemini settings exists" "${HOME}/.gemini/settings.json"
assert_file_contains "gemini has mcpServers" "${HOME}/.gemini/settings.json" "mcpServers"

# --- skills sync ---
echo "-- skills --"
assert_file_exists "claude skills synced" "${HOME}/.claude/skills/kb-troubleshooting/SKILL.md"
assert_file_exists "gemini skills synced" "${HOME}/.gemini/skills/kb-troubleshooting/SKILL.md"
assert_file_exists "codex skills synced" "${HOME}/.codex/skills/kb-troubleshooting/SKILL.md"
assert_file_exists "claude agents synced" "${HOME}/.claude/agents/app-test-debug-agent.md"
assert_file_exists "gemini agents synced" "${HOME}/.gemini/agents/app-test-debug-agent.md"
assert_file_exists "codex agents synced" "${HOME}/.codex/agents/app-test-debug-agent.md"
assert_file_not_exists "legacy agents skills are not used" "${HOME}/.agents/skills/kb-troubleshooting/SKILL.md"
assert_file_contains "claude skill has claude path" "${HOME}/.claude/skills/sync-knowledge/SKILL.md" "${HOME}/.claude/skills"
assert_file_contains "gemini skill has gemini path" "${HOME}/.gemini/skills/sync-knowledge/SKILL.md" "${HOME}/.gemini/skills"
assert_file_contains "codex skill has codex path" "${HOME}/.codex/skills/sync-knowledge/SKILL.md" "${HOME}/.codex/skills"

# --- local skill share ---
echo "-- local skill share --"
mkdir -p "${HOME}/.codex/skills/pj-local-share"
cat > "${HOME}/.codex/skills/pj-local-share/SKILL.md" <<'EOF'
# pj-local-share
path: {{SKILLS_DIR}}
EOF
assert_exit_0 "skill-share runs" "${SCRIPT}" skill-share pj-local-share
assert_file_exists "skill-share copied to claude" "${HOME}/.claude/skills/pj-local-share/SKILL.md"
assert_file_exists "skill-share copied to gemini" "${HOME}/.gemini/skills/pj-local-share/SKILL.md"
assert_file_contains "skill-share rendered claude path" "${HOME}/.claude/skills/pj-local-share/SKILL.md" "${HOME}/.claude/skills"
assert_file_contains "skill-share rendered gemini path" "${HOME}/.gemini/skills/pj-local-share/SKILL.md" "${HOME}/.gemini/skills"
assert_file_contains "skill-share rendered codex path" "${HOME}/.codex/skills/pj-local-share/SKILL.md" "${HOME}/.codex/skills"

mkdir -p "${TMP_WORK}/pj-promoted-skill"
cat > "${TMP_WORK}/pj-promoted-skill/SKILL.md" <<'EOF'
# pj-promoted-skill
path: {{SKILLS_DIR}}
EOF
assert_exit_0 "skill-promote from directory runs" "${SCRIPT}" skill-promote "${TMP_WORK}/pj-promoted-skill"
assert_file_exists "skill-promote copied to codex" "${HOME}/.codex/skills/pj-promoted-skill/SKILL.md"
assert_file_contains "skill-promote rendered codex path" "${HOME}/.codex/skills/pj-promoted-skill/SKILL.md" "${HOME}/.codex/skills"

mkdir -p "${HOME}/.claude/skills/pj-only-claude"
cat > "${HOME}/.claude/skills/pj-only-claude/SKILL.md" <<'EOF'
# pj-only-claude
path: {{SKILLS_DIR}}
EOF
mkdir -p "${HOME}/.gemini/skills/pj-only-gemini"
cat > "${HOME}/.gemini/skills/pj-only-gemini/SKILL.md" <<'EOF'
# pj-only-gemini
path: {{SKILLS_DIR}}
EOF
assert_exit_0 "skill-share-all runs" "${SCRIPT}" skill-share-all
assert_file_exists "skill-share-all claude copied" "${HOME}/.claude/skills/pj-only-gemini/SKILL.md"
assert_file_exists "skill-share-all codex copied" "${HOME}/.codex/skills/pj-only-claude/SKILL.md"
assert_exit_nonzero "skill-share rejects managed skills" "${SCRIPT}" skill-share kb-troubleshooting

# --- check (no drift after sync) ---
echo "-- check --"
assert_exit_0 "check passes after sync" "${SCRIPT}" check

# --- check detects drift ---
echo "-- check drift detection --"
echo "# tampered" >> "${HOME}/.claude/skills/sync-docs/SKILL.md"
assert_exit_nonzero "check detects skill drift" "${SCRIPT}" check
"${SCRIPT}" sync >/dev/null 2>&1
assert_exit_0 "check passes after re-sync" "${SCRIPT}" check
echo "# tampered" >> "${HOME}/.claude/agents/app-test-debug-agent.md"
assert_exit_nonzero "check detects claude agent drift" "${SCRIPT}" check
"${SCRIPT}" sync >/dev/null 2>&1
assert_exit_0 "check passes after claude agent re-sync" "${SCRIPT}" check
echo "# tampered" >> "${HOME}/.gemini/agents/app-test-debug-agent.md"
assert_exit_nonzero "check detects gemini agent drift" "${SCRIPT}" check
"${SCRIPT}" sync >/dev/null 2>&1
assert_exit_0 "check passes after gemini agent re-sync" "${SCRIPT}" check
echo "# tampered" >> "${HOME}/.codex/agents/app-test-debug-agent.md"
assert_exit_nonzero "check detects codex agent drift" "${SCRIPT}" check
"${SCRIPT}" sync >/dev/null 2>&1
assert_exit_0 "check passes after codex agent re-sync" "${SCRIPT}" check

# --- global instructions: absent ---
echo "-- global instructions (absent) --"
rm -f "${SCRIPT_DIR}/ai-config/global-instructions.md"
rm -f "${HOME}/.claude/CLAUDE.md" "${HOME}/.codex/AGENTS.md" "${HOME}/.gemini/GEMINI.md"
"${SCRIPT}" sync >/dev/null 2>&1
assert_file_not_exists "no CLAUDE.md when no master" "${HOME}/.claude/CLAUDE.md"
assert_file_not_exists "no AGENTS.md when no master" "${HOME}/.codex/AGENTS.md"
assert_file_not_exists "no GEMINI.md when no master" "${HOME}/.gemini/GEMINI.md"

# --- global instructions: present ---
echo "-- global instructions (present) --"
cat > "${SCRIPT_DIR}/ai-config/global-instructions.md" <<'EOF'
# Test Instructions
Always respond in 日本語.
EOF
"${SCRIPT}" sync >/dev/null 2>&1
assert_file_exists "CLAUDE.md created" "${HOME}/.claude/CLAUDE.md"
assert_file_exists "AGENTS.md created" "${HOME}/.codex/AGENTS.md"
assert_file_exists "GEMINI.md created" "${HOME}/.gemini/GEMINI.md"
assert_files_equal "CLAUDE.md matches AGENTS.md" "${HOME}/.claude/CLAUDE.md" "${HOME}/.codex/AGENTS.md"
assert_files_equal "CLAUDE.md matches GEMINI.md" "${HOME}/.claude/CLAUDE.md" "${HOME}/.gemini/GEMINI.md"

# --- global instructions: layered ---
echo "-- global instructions (layered) --"
cat > "${SCRIPT_DIR}/ai-config/global-instructions.local.md" <<'EOF'
# Local Override
Machine-specific note.
EOF
"${SCRIPT}" sync >/dev/null 2>&1
assert_file_contains "CLAUDE.md has base" "${HOME}/.claude/CLAUDE.md" "Test Instructions"
assert_file_contains "CLAUDE.md has local" "${HOME}/.claude/CLAUDE.md" "Local Override"
rm -f "${SCRIPT_DIR}/ai-config/global-instructions.local.md"

# --- check with instructions drift ---
echo "-- check instructions drift --"
echo "# tampered" >> "${HOME}/.claude/CLAUDE.md"
assert_exit_nonzero "check detects instructions drift" "${SCRIPT}" check
"${SCRIPT}" sync >/dev/null 2>&1
assert_exit_0 "check passes after instructions re-sync" "${SCRIPT}" check

# --- dry-run does not modify ---
echo "-- dry-run --"
SETTINGS_BEFORE="$(mktemp)"
cp "${HOME}/.claude/settings.json" "${SETTINGS_BEFORE}"
"${SCRIPT}" sync --dry-run >/dev/null 2>&1
assert_files_equal "dry-run did not change settings" "${HOME}/.claude/settings.json" "${SETTINGS_BEFORE}"
rm -f "${SETTINGS_BEFORE}"
SETTINGS_BEFORE=""

# --- user reset modes ---
echo "-- user reset modes --"
assert_exit_0 "wipe-user dry-run runs" "${SCRIPT}" wipe-user --dry-run
assert_exit_0 "wipe-user runs" "${SCRIPT}" wipe-user
assert_file_not_exists "wipe-user removed codex config" "${HOME}/.codex/config.toml"
assert_file_not_exists "wipe-user removed claude settings" "${HOME}/.claude/settings.json"
assert_file_not_exists "wipe-user removed claude agents" "${HOME}/.claude/agents/app-test-debug-agent.md"
assert_file_not_exists "wipe-user removed codex agents" "${HOME}/.codex/agents/app-test-debug-agent.md"
assert_file_not_exists "wipe-user removed gemini settings" "${HOME}/.gemini/settings.json"
assert_file_not_exists "wipe-user removed gemini agents" "${HOME}/.gemini/agents/app-test-debug-agent.md"

assert_exit_0 "reset-user dry-run runs" bash -lc "cd \"${SCRIPT_DIR}\" && \"${SCRIPT}\" reset-user --dry-run"
assert_exit_0 "reset-user restores from git config" bash -lc "cd \"${SCRIPT_DIR}\" && \"${SCRIPT}\" reset-user"
assert_file_exists "reset-user restored codex config" "${HOME}/.codex/config.toml"
assert_file_exists "reset-user restored claude settings" "${HOME}/.claude/settings.json"
assert_file_exists "reset-user restored gemini settings" "${HOME}/.gemini/settings.json"

# --- status ---
echo "-- status --"
assert_exit_0 "status runs" "${SCRIPT}" status

echo ""
echo "=========================================="
printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "${PASS}" "${FAIL}"
echo "=========================================="

if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
