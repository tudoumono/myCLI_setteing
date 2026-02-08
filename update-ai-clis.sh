#!/usr/bin/env bash
# update-ai-clis.sh
# Unified manager for Claude Code / Gemini CLI / Codex CLI and MCP settings.
set -euo pipefail
# Ensure required commands are discoverable in non-interactive shells (cron/CI/WSL).
export PATH="${HOME}/.local/bin:${HOME}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/ai-config"
BASE_REGISTRY_FILE="${CONFIG_DIR}/base.json"
BASE_LOCK_FILE="${CONFIG_DIR}/base.lock.sha256"
PROJECTS_DIR="${CONFIG_DIR}/projects"
GLOBAL_LOCAL_FILE="${CONFIG_DIR}/local.json"
CODEX_BASE_FILE="${CONFIG_DIR}/codex-base.toml"
SKILLS_MASTER_DIR="${CONFIG_DIR}/skills"
GLOBAL_INSTRUCTIONS="${CONFIG_DIR}/global-instructions.md"
GLOBAL_INSTRUCTIONS_LOCAL="${CONFIG_DIR}/global-instructions.local.md"

CLAUDE_JSON="${HOME}/.claude.json"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
CODEX_TOML="${HOME}/.codex/config.toml"
GEMINI_SETTINGS="${HOME}/.gemini/settings.json"
GEMINI_MCP_MANAGED="${HOME}/.gemini/mcp.managed.json"
CLAUDE_SKILLS_DIR="${HOME}/.claude/skills"
GEMINI_SKILLS_DIR="${HOME}/.gemini/skills"
CODEX_SKILLS_DIR="${HOME}/.codex/skills"

RUN_TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${CONFIG_DIR}/backups/${RUN_TS}"

EFFECTIVE_REGISTRY=""
EFFECTIVE_LAYERS=""
ACTIVE_PROJECT_REF=""
DRY_RUN=0

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
divider() { printf '%s\n' "------------------------------------------"; }

usage() {
  cat <<'USAGE_EOF'
Usage:
  ./update-ai-clis.sh init
  ./update-ai-clis.sh lock-base
  ./update-ai-clis.sh project-init [project_dir]
  ./update-ai-clis.sh update
  ./update-ai-clis.sh sync [project]
  ./update-ai-clis.sh sync-here
  ./update-ai-clis.sh reset [project]
  ./update-ai-clis.sh reset-here
  ./update-ai-clis.sh all [project]
  ./update-ai-clis.sh all-here
  ./update-ai-clis.sh diff [project]
  ./update-ai-clis.sh check [project]
  ./update-ai-clis.sh status [project]
  ./update-ai-clis.sh status-here
  ./update-ai-clis.sh <sync|reset|all> [project] --dry-run

Commands:
  init    Create baseline files under ai-config/.
  lock-base  Refresh and lock base.json hash (for intentional base update only).
  project-init  Initialize per-project overlay from current directory (or given path) and run sync.
  update  Update Claude/Gemini/Codex CLIs via npm.
  sync    Apply unified config (Global + Project + Folder local overlay).
  sync-here  Apply sync with project = current directory.
  reset   Reset to baseline (clear MCP config + uninstall registered MCP packages).
  reset-here  Reset using project = current directory.
  all     Run update then sync.
  all-here  Run update then sync with project = current directory.
  diff    Show what `sync` would change without writing real files.
  check   Verify master matches deployed state; exit non-zero on drift (CI-friendly).
  status  Show versions and effective configuration status.
  status-here  Show status with project = current directory.
  --dry-run  Preview changes for sync/reset/all without applying.

Layer order (later overrides earlier):
  1) ai-config/base.json               (Global)
  2) ai-config/projects/<project>.json (Project, optional)
  3) ai-config/local.json              (Machine local, optional)
  4) ./.ai-stack.local.json            (Folder local, optional)
USAGE_EOF
}

cleanup_effective_registry() {
  if [[ -n "${EFFECTIVE_REGISTRY}" && -f "${EFFECTIVE_REGISTRY}" ]]; then
    rm -f "${EFFECTIVE_REGISTRY}"
  fi
  EFFECTIVE_REGISTRY=""
  EFFECTIVE_LAYERS=""
}
trap cleanup_effective_registry EXIT

ensure_node() {
  if ! command -v node >/dev/null 2>&1; then
    error "node is required but not found."
    exit 1
  fi
}

ensure_parent_dir() {
  local f="$1"
  mkdir -p "$(dirname "${f}")"
}

has_exact_line() {
  local line="$1"
  local file="$2"
  grep -qFx "${line}" "${file}" 2>/dev/null
}

write_codex_base_template() {
  local out_path="$1"
  cat > "${out_path}" <<'EOF_CODEX_BASE'
# Codex baseline managed by update-ai-clis.sh
model = "gpt-5.3-codex"
personality = "pragmatic"
model_reasoning_effort = "xhigh"

[projects."/root"]
trust_level = "trusted"

[features]
shell_snapshot = true
collab = true
apps = true

[tools]
web_search = true
EOF_CODEX_BASE
}

ensure_codex_base_file() {
  ensure_parent_dir "${CODEX_BASE_FILE}"
  if [[ ! -f "${CODEX_BASE_FILE}" ]]; then
    write_codex_base_template "${CODEX_BASE_FILE}"
    info "Created Codex baseline: ${CODEX_BASE_FILE}"
  fi
}

escape_sed_replacement() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/[&|]/\\&/g'
}

ensure_skills_master() {
  mkdir -p "${SKILLS_MASTER_DIR}"

  if [[ ! -f "${SKILLS_MASTER_DIR}/README.md" ]]; then
    cat > "${SKILLS_MASTER_DIR}/README.md" <<'EOF_SKILLS_README'
# skills master

`ai-config/skills` is the single source of truth for user skills.

Synced targets:

- `~/.claude/skills`
- `~/.gemini/skills`
- `~/.codex/skills`
EOF_SKILLS_README
  fi

  if find "${SKILLS_MASTER_DIR}" -mindepth 1 -maxdepth 1 -type d | read -r; then
    return 0
  fi

  if [[ ! -d "${CLAUDE_SKILLS_DIR}" ]]; then
    return 0
  fi

  local imported=0
  local src
  local name
  while IFS= read -r -d '' src; do
    name="$(basename "${src}")"
    [[ "${name}" == .* ]] && continue
    [[ -f "${src}/SKILL.md" ]] || continue
    cp -a "${src}" "${SKILLS_MASTER_DIR}/${name}"
    imported=$((imported + 1))
  done < <(find "${CLAUDE_SKILLS_DIR}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

  if [[ "${imported}" -gt 0 ]]; then
    info "Seeded skills master from ${CLAUDE_SKILLS_DIR}: ${imported} skills"
  fi
}

list_master_skill_names() {
  [[ -d "${SKILLS_MASTER_DIR}" ]] || return 0
  local dir
  local name
  while IFS= read -r -d '' dir; do
    name="$(basename "${dir}")"
    [[ "${name}" == .* ]] && continue
    [[ -f "${dir}/SKILL.md" ]] || continue
    printf "%s\n" "${name}"
  done < <(find "${SKILLS_MASTER_DIR}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
}

render_skill_for_target() {
  local skill_md="$1"
  local target_skills_dir="$2"
  [[ -f "${skill_md}" ]] || return 0
  local escaped
  escaped="$(escape_sed_replacement "${target_skills_dir}")"
  sed -i \
    -e "s|{{SKILLS_DIR}}|${escaped}|g" \
    -e "s|__SKILLS_DIR__|${escaped}|g" \
    -e "s|~/.claude/skills|${escaped}|g" \
    -e "s|/root/.claude/skills|${escaped}|g" \
    "${skill_md}"
}

sync_skills_to_target() {
  local target_dir="$1"
  local manifest="${target_dir}/.ai-stack.managed-skills"
  local tmp_manifest
  tmp_manifest="$(mktemp)"

  mkdir -p "${target_dir}"

  local skill_name
  local src_dir
  local dst_dir
  while IFS= read -r skill_name; do
    [[ -n "${skill_name}" ]] || continue
    src_dir="${SKILLS_MASTER_DIR}/${skill_name}"
    dst_dir="${target_dir}/${skill_name}"
    rm -rf "${dst_dir}"
    mkdir -p "${dst_dir}"
    cp -a "${src_dir}/." "${dst_dir}/"
    render_skill_for_target "${dst_dir}/SKILL.md" "${target_dir}"
    printf "%s\n" "${skill_name}" >> "${tmp_manifest}"
  done < <(list_master_skill_names | sort)

  if [[ -f "${manifest}" ]]; then
    local stale
    while IFS= read -r stale; do
      [[ -n "${stale}" ]] || continue
      if ! grep -qFx "${stale}" "${tmp_manifest}" 2>/dev/null; then
        rm -rf "${target_dir}/${stale}"
      fi
    done < "${manifest}"
  fi

  mv "${tmp_manifest}" "${manifest}"
  chmod 644 "${manifest}" 2>/dev/null || true
}

count_skills_in_dir() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    echo "0"
    return 0
  fi
  local count
  count="$(find "${dir}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | while IFS= read -r d; do
    if [[ -f "${d}/SKILL.md" ]]; then
      echo 1
    fi
  done | wc -l | tr -d ' ')"
  echo "${count:-0}"
}

sync_skills() {
  ensure_skills_master

  local master_count
  master_count="$(count_skills_in_dir "${SKILLS_MASTER_DIR}")"
  if [[ "${master_count}" -eq 0 ]]; then
    warn "No master skills found in ${SKILLS_MASTER_DIR}; skip skill sync."
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: skip skill distribution (master skills: ${master_count})."
    return 0
  fi

  # Migrate away from legacy path to prevent duplicated skill discovery.
  local legacy_agents_dir="${HOME}/.agents/skills"
  local legacy_manifest="${legacy_agents_dir}/.ai-stack.managed-skills"
  if [[ -d "${legacy_agents_dir}" ]]; then
    if [[ -f "${legacy_manifest}" ]]; then
      while IFS= read -r legacy_skill; do
        [[ -n "${legacy_skill}" ]] || continue
        rm -rf "${legacy_agents_dir}/${legacy_skill}"
      done < "${legacy_manifest}"
      rm -f "${legacy_manifest}"
      rmdir "${legacy_agents_dir}" 2>/dev/null || true
      info "Removed legacy managed skills: ${legacy_agents_dir}"
    else
      warn "Legacy skills dir exists and is unmanaged: ${legacy_agents_dir}"
      warn "To avoid duplicate listings in Codex, remove it manually if not needed."
    fi
  fi

  sync_skills_to_target "${CLAUDE_SKILLS_DIR}"
  sync_skills_to_target "${GEMINI_SKILLS_DIR}"
  sync_skills_to_target "${CODEX_SKILLS_DIR}"
  info "Synced skills: master=${master_count}, targets=claude/gemini/codex"
}

sha256_short() {
  local f="$1"
  sha256_of_file "${f}" | cut -c1-12
}

dir_content_hash() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    echo "n/a"
    return 0
  fi
  find "${dir}" -type f ! -name '.*' -print0 2>/dev/null \
    | sort -z \
    | xargs -0 cat 2>/dev/null \
    | sha256_of_stdin
}

sha256_of_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
    return 0
  fi
  echo "n/a"
}

build_merged_instructions() {
  local project_ref="${ACTIVE_PROJECT_REF}"
  local merged
  merged="$(mktemp)"

  if [[ -f "${GLOBAL_INSTRUCTIONS}" ]]; then
    cat "${GLOBAL_INSTRUCTIONS}" >> "${merged}"
  fi

  if [[ -n "${project_ref}" ]]; then
    local project_name=""
    if [[ -d "${project_ref}" ]]; then
      project_name="$(basename "${project_ref}")"
    elif [[ -f "${project_ref}" ]]; then
      project_name="$(basename "${project_ref}" .json)"
    else
      project_name="${project_ref}"
    fi
    local project_instructions="${PROJECTS_DIR}/${project_name}.instructions.md"
    if [[ -f "${project_instructions}" ]]; then
      [[ -s "${merged}" ]] && printf "\n" >> "${merged}"
      cat "${project_instructions}" >> "${merged}"
    fi
  fi

  if [[ -f "${GLOBAL_INSTRUCTIONS_LOCAL}" ]]; then
    [[ -s "${merged}" ]] && printf "\n" >> "${merged}"
    cat "${GLOBAL_INSTRUCTIONS_LOCAL}" >> "${merged}"
  fi

  if [[ ! -s "${merged}" ]]; then
    rm -f "${merged}"
    echo ""
    return 0
  fi
  echo "${merged}"
}

sync_global_instructions() {
  local merged
  merged="$(build_merged_instructions)"
  if [[ -z "${merged}" ]]; then
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: would distribute merged instructions to CLAUDE.md / AGENTS.md / GEMINI.md"
    rm -f "${merged}"
    return 0
  fi

  local targets=(
    "${HOME}/.claude/CLAUDE.md"
    "${HOME}/.codex/AGENTS.md"
    "${HOME}/.gemini/GEMINI.md"
  )
  local dst
  for dst in "${targets[@]}"; do
    ensure_parent_dir "${dst}"
    backup_file "${dst}"
    cp "${merged}" "${dst}"
  done
  rm -f "${merged}"
  info "Synced global instructions: ${#targets[@]} targets"
}

sha256_of_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${f}" | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${f}" | awk '{print $1}'
    return 0
  fi
  error "sha256sum/shasum not found."
  exit 1
}

write_base_lock() {
  local hash
  hash="$(sha256_of_file "${BASE_REGISTRY_FILE}")"
  printf "%s\n" "${hash}" > "${BASE_LOCK_FILE}"
  chmod 644 "${BASE_LOCK_FILE}" 2>/dev/null || true
  chmod a-w "${BASE_REGISTRY_FILE}" 2>/dev/null || true
}

ensure_base_lock() {
  if [[ ! -f "${BASE_LOCK_FILE}" ]]; then
    write_base_lock
    info "Created base lock: ${BASE_LOCK_FILE}"
  fi
}

validate_base_locked() {
  ensure_base_lock
  local expected
  local actual
  expected="$(tr -d '[:space:]' < "${BASE_LOCK_FILE}")"
  actual="$(sha256_of_file "${BASE_REGISTRY_FILE}")"
  if [[ -z "${expected}" || "${expected}" != "${actual}" ]]; then
    error "base.json changed and is locked. Keep base as main baseline."
    error "Add extra features in projects/<name>.json or .ai-stack.local.json."
    error "If this base change is intentional, run: ./update-ai-clis.sh lock-base"
    exit 1
  fi
}

resolve_abs_path() {
  local p="$1"
  if [[ ! -e "${p}" ]]; then
    error "Path not found: ${p}"
    exit 1
  fi
  if command -v realpath >/dev/null 2>&1; then
    realpath "${p}"
    return 0
  fi
  (
    cd "${p}" >/dev/null 2>&1
    pwd
  )
}

assert_not_setupscript_dir() {
  local target="$1"
  if [[ "${target}" == "${SCRIPT_DIR}" ]]; then
    error "Current target is setupScript itself. Move to project folder or pass project path."
    exit 1
  fi
}

backup_file() {
  local src="$1"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  [[ -e "${src}" ]] || return 0
  local rel="${src#/}"
  local dst="${BACKUP_DIR}/${rel}"
  mkdir -p "$(dirname "${dst}")"
  cp -a "${src}" "${dst}"
}

show_version() {
  local name="$1" cmd="$2"
  if command -v "${cmd}" >/dev/null 2>&1; then
    printf "  %-16s %s\n" "${name}:" "$("${cmd}" --version 2>/dev/null || echo 'unknown')"
  else
    printf "  %-16s %s\n" "${name}:" "not installed"
  fi
}

show_versions() {
  echo ""
  info "Current versions:"
  show_version "Claude Code" claude
  show_version "Gemini CLI" gemini
  show_version "Codex CLI" codex
}

run_npm_update() {
  local label="$1"
  local pkg="$2"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: npm update -g ${pkg}"
    return 0
  fi
  info "Updating ${label} (${pkg}) ..."
  if npm update -g "${pkg}" >/dev/null 2>&1; then
    info "${label} updated successfully."
  else
    warn "${label} update failed."
  fi
}

update_clis() {
  show_versions
  divider
  run_npm_update "Claude Code" "@anthropic-ai/claude-code"
  divider
  run_npm_update "Gemini CLI" "@google/gemini-cli"
  divider
  run_npm_update "Codex CLI" "@openai/codex"
  divider
  info "Updated versions:"
  show_version "Claude Code" claude
  show_version "Gemini CLI" gemini
  show_version "Codex CLI" codex
}

bootstrap_config_files() {
  mkdir -p "${CONFIG_DIR}" "${PROJECTS_DIR}" "${CONFIG_DIR}/backups"

  if [[ ! -f "${BASE_REGISTRY_FILE}" ]]; then
    cat > "${BASE_REGISTRY_FILE}" <<'EOF_BASE'
{
  "defaults": {
    "language": {
      "claude": "日本語",
      "codex": "日本語",
      "gemini": "日本語"
    },
    "webSearch": {
      "claude": true,
      "codex": true,
      "gemini": true
    }
  },
  "global": {
    "claudeServers": [
      "context7"
    ]
  },
  "servers": {
    "context7": {
      "enabled": true,
      "command": "npx",
      "args": [
        "-y",
        "@upstash/context7-mcp"
      ],
      "targets": [
        "claude",
        "codex",
        "gemini"
      ],
      "delivery": {
        "claude": "plugin",
        "codex": "config",
        "gemini": "settings"
      },
      "npm_package": "@upstash/context7-mcp"
    }
  },
  "projects": {},
  "uninstall": {
    "npm": [
      "@upstash/context7-mcp"
    ],
    "pipx": [
      "serena-agent"
    ]
  }
}
EOF_BASE
    info "Created baseline config: ${BASE_REGISTRY_FILE}"
  fi

  ensure_codex_base_file

  if [[ ! -f "${PROJECTS_DIR}/_example.json" ]]; then
    cat > "${PROJECTS_DIR}/_example.json" <<'EOF_PROJECT'
{
  "projects": {
    "/root/mywork/example-project": [
      "context7"
    ]
  },
  "servers": {
    "context7": {
      "enabled": true
    }
  }
}
EOF_PROJECT
    info "Created project overlay template: ${PROJECTS_DIR}/_example.json"
  fi

  if [[ ! -f "${CONFIG_DIR}/README.md" ]]; then
    cat > "${CONFIG_DIR}/README.md" <<'EOF_README'
# ai-config

Layered configuration for Claude/Codex/Gemini baseline.
Main baseline (`base.json`) is intentionally locked.

## Files

- `base.json`: Global baseline (required, locked)
- `base.lock.sha256`: Lock hash for `base.json`
- `projects/<name>.json`: Project overlay (optional)
- `local.json`: Machine-local overlay (optional, do not commit)
- `.ai-stack.local.json`: Folder-local overlay (optional, do not commit)

## Priority

`base.json` < `projects/<name>.json` < `local.json` < `.ai-stack.local.json`

## Recommended workflow

1. Keep `base.json` as stable minimal baseline.
2. Add project-specific features in `projects/<name>.json`.
3. Keep secrets/path overrides in `local.json` or `.ai-stack.local.json`.
4. Run `./update-ai-clis.sh sync <name>`.

If you intentionally update `base.json`, run:

`./update-ai-clis.sh lock-base`
EOF_README
    info "Created docs: ${CONFIG_DIR}/README.md"
  fi

  ensure_skills_master

  ensure_base_lock
}

project_init() {
  ensure_node
  bootstrap_config_files
  validate_base_locked

  local raw_project_dir="${1:-$PWD}"
  if [[ ! -d "${raw_project_dir}" ]]; then
    error "Project directory not found: ${raw_project_dir}"
    exit 1
  fi

  local project_dir
  local project_name
  local project_overlay
  local folder_overlay
  local gitignore

  project_dir="$(resolve_abs_path "${raw_project_dir}")"
  assert_not_setupscript_dir "${project_dir}"
  project_name="$(basename "${project_dir}")"
  project_overlay="${PROJECTS_DIR}/${project_name}.json"
  folder_overlay="${project_dir}/.ai-stack.local.json"
  gitignore="${project_dir}/.gitignore"

  if [[ -f "${project_overlay}" ]]; then
    info "Project overlay already exists: ${project_overlay}"
  else
    node - "${project_overlay}" "${project_dir}" <<'NODE'
const fs = require("fs");
const outPath = process.argv[2];
const projectDir = process.argv[3];
const json = {
  projects: {
    [projectDir]: []
  },
  servers: {}
};
fs.writeFileSync(outPath, JSON.stringify(json, null, 2) + "\n");
NODE
    info "Created project overlay: ${project_overlay}"
  fi

  if [[ -f "${folder_overlay}" ]]; then
    info "Folder local overlay exists: ${folder_overlay}"
  else
    cat > "${folder_overlay}" <<'EOF_LOCAL'
{
  "servers": {}
}
EOF_LOCAL
    info "Created folder local overlay: ${folder_overlay}"
  fi

  if [[ -f "${gitignore}" ]]; then
    if ! has_exact_line ".ai-stack.local.json" "${gitignore}"; then
      echo ".ai-stack.local.json" >> "${gitignore}"
      info "Updated .gitignore: ${gitignore}"
    fi
  else
    echo ".ai-stack.local.json" > "${gitignore}"
    info "Created .gitignore: ${gitignore}"
  fi

  ACTIVE_PROJECT_REF="${project_dir}"
  sync_all
}

build_effective_registry() {
  ensure_node
  bootstrap_config_files
  validate_base_locked

  local project_ref="${1:-}"
  ACTIVE_PROJECT_REF="${project_ref}"

  local project_file=""
  local folder_local_file="${PWD}/.ai-stack.local.json"

  if [[ -n "${project_ref}" ]]; then
    if [[ -f "${project_ref}" ]]; then
      project_file="${project_ref}"
      folder_local_file="$(dirname "${project_ref}")/.ai-stack.local.json"
    elif [[ -f "${PROJECTS_DIR}/${project_ref}.json" ]]; then
      project_file="${PROJECTS_DIR}/${project_ref}.json"
    elif [[ -d "${project_ref}" ]]; then
      local name
      name="$(basename "${project_ref}")"
      if [[ -f "${PROJECTS_DIR}/${name}.json" ]]; then
        project_file="${PROJECTS_DIR}/${name}.json"
      fi
      folder_local_file="${project_ref}/.ai-stack.local.json"
    else
      warn "Project overlay not found for '${project_ref}'. Using Global config only."
    fi
  fi

  cleanup_effective_registry
  EFFECTIVE_REGISTRY="$(mktemp)"

EFFECTIVE_LAYERS="$(node - "${BASE_REGISTRY_FILE}" "${project_file}" "${GLOBAL_LOCAL_FILE}" "${folder_local_file}" "${EFFECTIVE_REGISTRY}" "${project_ref}" <<'NODE'
const fs = require("fs");

const basePath = process.argv[2];
const projectPath = process.argv[3];
const globalLocalPath = process.argv[4];
const folderLocalPath = process.argv[5];
const outPath = process.argv[6];
const projectRef = process.argv[7] || "";

function existsFile(p) {
  return typeof p === "string" && p.length > 0 && fs.existsSync(p) && fs.statSync(p).isFile();
}

function isObject(v) {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function mergeDeep(base, overlay) {
  if (Array.isArray(base) && Array.isArray(overlay)) {
    return overlay.slice();
  }
  if (isObject(base) && isObject(overlay)) {
    const out = { ...base };
    for (const [k, v] of Object.entries(overlay)) {
      if (!(k in out)) {
        out[k] = v;
      } else {
        out[k] = mergeDeep(out[k], v);
      }
    }
    return out;
  }
  return overlay;
}

function loadJson(path, label, required = false) {
  if (!existsFile(path)) {
    if (required) {
      throw new Error(`Required file not found: ${path}`);
    }
    return null;
  }
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(path, "utf8"));
  } catch (err) {
    const msg = err && err.message ? err.message : String(err);
    throw new Error(`Invalid JSON in ${label} (${path}): ${msg}`);
  }
  return { path, label, parsed };
}

try {
  const sources = [];
  const candidates = [
    loadJson(basePath, "global", true),
    loadJson(projectPath, "project", false),
    loadJson(globalLocalPath, "machine-local", false),
    loadJson(folderLocalPath, "folder-local", false)
  ].filter(Boolean);

  let merged = {};
  for (const src of candidates) {
    merged = mergeDeep(merged, src.parsed);
    sources.push({ label: src.label, path: src.path });
  }

  if (!isObject(merged.defaults)) merged.defaults = {};
  if (!isObject(merged.servers)) merged.servers = {};
  if (!isObject(merged.projects)) merged.projects = {};
  if (!isObject(merged.uninstall)) merged.uninstall = {};
  if (!isObject(merged.global)) merged.global = {};

  merged._meta = {
    generatedAt: new Date().toISOString(),
    projectRef,
    sources
  };

  fs.writeFileSync(outPath, JSON.stringify(merged, null, 2) + "\n");
  process.stdout.write(sources.map(s => `${s.label}:${s.path}`).join(" | "));
} catch (err) {
  const msg = err && err.message ? err.message : String(err);
  console.error(`Failed to build merged config: ${msg}`);
  process.exit(1);
}
NODE
)"
}

strip_codex_mcp_sections() {
  local src="$1"
  awk '
    BEGIN { in_managed_block=0; in_mcp_section=0 }
    /^[[:space:]]*# BEGIN MANAGED MCP \(ai-stack\)/ { in_managed_block=1; next }
    /^[[:space:]]*# END MANAGED MCP \(ai-stack\)/   { in_managed_block=0; next }
    in_managed_block { next }

    /^[[:space:]]*\[mcp_servers(\.|])/{ in_mcp_section=1; next }
    /^[[:space:]]*\[/ {
      if (in_mcp_section == 1) {
        in_mcp_section=0
      }
    }
    in_mcp_section { next }
    { print }
  ' "${src}"
}

build_codex_mcp_toml() {
  node - "${EFFECTIVE_REGISTRY}" <<'NODE'
const fs = require("fs");
const registryPath = process.argv[2];
const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const servers = registry.servers || {};

function targetEnabled(server, target) {
  if (!server || typeof server !== "object") return false;
  if (server.enabled === false) return false;
  if (server.delivery && server.delivery[target] === "disabled") return false;
  const targets = server.targets;
  if (!Array.isArray(targets) || targets.length === 0) return true;
  return targets.includes(target);
}

function resolveEnvValue(value) {
  if (typeof value !== "string") return String(value ?? "");
  const match = value.match(/^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$/);
  if (!match) return value;
  return process.env[match[1]] || "";
}

function q(value) {
  return JSON.stringify(String(value));
}

function tableKey(key) {
  return JSON.stringify(String(key));
}

function envKey(key) {
  const s = String(key);
  return /^[A-Za-z_][A-Za-z0-9_-]*$/.test(s) ? s : q(s);
}

const names = Object.keys(servers).sort();
let count = 0;
console.log("# BEGIN MANAGED MCP (ai-stack)");
for (const name of names) {
  const server = servers[name];
  if (!targetEnabled(server, "codex")) continue;
  if (server.type && server.type !== "stdio") continue;
  if (typeof server.command !== "string" || server.command.length === 0) continue;

  const args = Array.isArray(server.args) ? server.args : [];
  const env = server.env && typeof server.env === "object" && !Array.isArray(server.env)
    ? server.env
    : {};

  console.log(`[mcp_servers.${tableKey(name)}]`);
  console.log(`command = ${q(server.command)}`);
  console.log(`args = [${args.map(q).join(", ")}]`);

  const envEntries = Object.entries(env)
    .map(([k, v]) => [k, resolveEnvValue(v)])
    .filter(([, v]) => v.length > 0);
  if (envEntries.length > 0) {
    const inline = envEntries.map(([k, v]) => `${envKey(k)} = ${q(v)}`).join(", ");
    console.log(`env = { ${inline} }`);
  }
  console.log("");
  count += 1;
}
console.log(`# managed_servers = ${count}`);
console.log("# END MANAGED MCP (ai-stack)");
NODE
}

ensure_codex_config() {
  ensure_codex_base_file
  ensure_parent_dir "${CODEX_TOML}"
  if [[ ! -f "${CODEX_TOML}" ]]; then
    cp "${CODEX_BASE_FILE}" "${CODEX_TOML}"
  fi
  chmod 600 "${CODEX_TOML}" 2>/dev/null || true
}

ensure_codex_web_search_default() {
  ensure_codex_config
  backup_file "${CODEX_TOML}"

  local tmp
  tmp="$(mktemp)"

  awk '
    BEGIN {
      in_tools=0;
      seen_tools=0;
      seen_web=0;
    }
    /^[[:space:]]*\[tools\][[:space:]]*$/ {
      in_tools=1;
      seen_tools=1;
      print;
      next;
    }
    /^[[:space:]]*\[/ {
      if (in_tools == 1 && seen_web == 0) {
        print "web_search = true";
        seen_web=1;
      }
      in_tools=0;
    }
    {
      if (in_tools == 1 && $0 ~ /^[[:space:]]*web_search[[:space:]]*=/) {
        if (seen_web == 0) {
          print "web_search = true";
          seen_web=1;
        }
        next;
      }
      print;
    }
    END {
      if (seen_tools == 0) {
        print "";
        print "[tools]";
        print "web_search = true";
      } else if (in_tools == 1 && seen_web == 0) {
        print "web_search = true";
      }
    }
  ' "${CODEX_TOML}" > "${tmp}"

  mv "${tmp}" "${CODEX_TOML}"
  chmod 600 "${CODEX_TOML}" 2>/dev/null || true
}

sync_codex_mcp() {
  ensure_codex_config
  backup_file "${CODEX_TOML}"

  local tmp_clean
  local tmp_mcp
  tmp_clean="$(mktemp)"
  tmp_mcp="$(mktemp)"

  strip_codex_mcp_sections "${CODEX_TOML}" | awk '
    { lines[NR] = $0 }
    END {
      n = NR
      while (n > 0 && lines[n] ~ /^[[:space:]]*$/) {
        n--
      }
      for (i = 1; i <= n; i++) {
        print lines[i]
      }
    }
  ' > "${tmp_clean}"
  build_codex_mcp_toml > "${tmp_mcp}"

  {
    if [[ -s "${tmp_clean}" ]]; then
      cat "${tmp_clean}"
      echo ""
    fi
    cat "${tmp_mcp}"
    echo ""
  } > "${CODEX_TOML}"

  rm -f "${tmp_clean}" "${tmp_mcp}"
  chmod 600 "${CODEX_TOML}" 2>/dev/null || true
  info "Synced Codex MCP config: ${CODEX_TOML}"
}

sync_claude_mcp() {
  ensure_parent_dir "${CLAUDE_JSON}"
  backup_file "${CLAUDE_JSON}"

  node - "${EFFECTIVE_REGISTRY}" "${CLAUDE_JSON}" <<'NODE'
const fs = require("fs");
const registryPath = process.argv[2];
const claudePath = process.argv[3];

const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const servers = registry.servers || {};
const projectMapping = registry.projects || {};
const global = registry.global || {};

let claude = {};
if (fs.existsSync(claudePath)) {
  try {
    claude = JSON.parse(fs.readFileSync(claudePath, "utf8"));
  } catch {
    claude = {};
  }
}

if (!claude.projects || typeof claude.projects !== "object" || Array.isArray(claude.projects)) {
  claude.projects = {};
}
if (!claude.mcpServers || typeof claude.mcpServers !== "object" || Array.isArray(claude.mcpServers)) {
  claude.mcpServers = {};
}

function targetEnabled(server, target) {
  if (!server || typeof server !== "object") return false;
  if (server.enabled === false) return false;
  if (server.delivery && server.delivery[target] === "disabled") return false;
  const targets = server.targets;
  if (!Array.isArray(targets) || targets.length === 0) return true;
  return targets.includes(target);
}

function resolveEnvValue(value) {
  if (typeof value !== "string") return String(value ?? "");
  const match = value.match(/^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$/);
  if (!match) return value;
  return process.env[match[1]] || "";
}

function buildServer(name) {
  const server = servers[name];
  if (!targetEnabled(server, "claude")) return null;

  if (server.type === "http") {
    if (typeof server.url !== "string" || server.url.length === 0) return null;
    return {
      type: "http",
      url: server.url
    };
  }

  if (typeof server.command !== "string" || server.command.length === 0) return null;
  const args = Array.isArray(server.args) ? server.args : [];
  const out = {
    type: "stdio",
    command: server.command,
    args
  };

  const env = server.env && typeof server.env === "object" && !Array.isArray(server.env)
    ? server.env
    : {};
  const resolvedEnv = {};
  for (const [k, v] of Object.entries(env)) {
    const rv = resolveEnvValue(v);
    if (rv.length > 0) resolvedEnv[k] = rv;
  }
  if (Object.keys(resolvedEnv).length > 0) out.env = resolvedEnv;
  return out;
}

const globalServerNames = Array.isArray(global.claudeServers)
  ? global.claudeServers
  : Object.keys(servers).filter((name) => targetEnabled(servers[name], "claude"));

const newGlobal = {};
for (const name of globalServerNames) {
  const built = buildServer(name);
  if (built) newGlobal[name] = built;
}
claude.mcpServers = newGlobal;

const managedProjects = new Set(Object.keys(projectMapping));
for (const [projectPath, projectValue] of Object.entries(claude.projects)) {
  if (managedProjects.has(projectPath)) continue;
  if (!projectValue || typeof projectValue !== "object" || Array.isArray(projectValue)) continue;
  delete projectValue.mcpServers;
  delete projectValue.mcpContextUris;
  if (Object.keys(projectValue).length === 0) {
    delete claude.projects[projectPath];
  }
}

for (const [projectPath, serverNamesRaw] of Object.entries(projectMapping)) {
  if (!claude.projects[projectPath] || typeof claude.projects[projectPath] !== "object" || Array.isArray(claude.projects[projectPath])) {
    claude.projects[projectPath] = {};
  }
  if (!Array.isArray(claude.projects[projectPath].mcpContextUris)) {
    claude.projects[projectPath].mcpContextUris = [];
  }

  const serverNames = Array.isArray(serverNamesRaw) ? serverNamesRaw : [];
  const mcpServers = {};
  for (const serverName of serverNames) {
    const built = buildServer(serverName);
    if (built) mcpServers[serverName] = built;
  }
  claude.projects[projectPath].mcpServers = mcpServers;
}

fs.writeFileSync(claudePath, JSON.stringify(claude, null, 2) + "\n");
const projectTotal = Object.values(claude.projects).reduce((acc, p) => acc + Object.keys((p && p.mcpServers) || {}).length, 0);
const total = Object.keys(claude.mcpServers || {}).length + projectTotal;
process.stdout.write(String(total));
NODE
}

sync_claude_settings_defaults() {
  ensure_parent_dir "${CLAUDE_SETTINGS}"
  backup_file "${CLAUDE_SETTINGS}"

  node - "${EFFECTIVE_REGISTRY}" "${CLAUDE_SETTINGS}" <<'NODE'
const fs = require("fs");
const registryPath = process.argv[2];
const settingsPath = process.argv[3];

const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const defaults = registry.defaults || {};

function resolveScoped(obj, key, fallback) {
  if (!obj || typeof obj !== "object") return fallback;
  const v = obj[key];
  if (typeof v === "string" || typeof v === "boolean") return v;
  if (v && typeof v === "object") {
    if (typeof v.claude === "string" || typeof v.claude === "boolean") return v.claude;
    if (typeof v.default === "string" || typeof v.default === "boolean") return v.default;
  }
  return fallback;
}

const desiredLanguage = resolveScoped(defaults, "language", "日本語");
const webSearchEnabled = resolveScoped(defaults, "webSearch", true) !== false;

let settings = {};
if (fs.existsSync(settingsPath)) {
  try {
    settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
  } catch {
    settings = {};
  }
}

if (!settings.permissions || typeof settings.permissions !== "object" || Array.isArray(settings.permissions)) {
  settings.permissions = {};
}
if (!Array.isArray(settings.permissions.allow)) {
  settings.permissions.allow = [];
}

function isLegacyReadBashRule(v) {
  if (typeof v !== "string") return false;
  if (!v.startsWith("Bash(") || !v.endsWith(")")) return false;
  const inner = v.slice(5, -1).trim().toLowerCase();
  const legacyCommands = [
    "cat",
    "ls",
    "find",
    "grep",
    "rg",
    "head",
    "tail",
    "wc",
    "stat",
    "file",
    "nl",
    "tree"
  ];
  return legacyCommands.some((cmd) => inner === cmd || inner.startsWith(`${cmd}:`));
}

const filteredAllow = settings.permissions.allow.filter((v) => {
  if (typeof v !== "string") return false;
  return !isLegacyReadBashRule(v);
});

const allowSet = new Set(filteredAllow);
allowSet.add("Read");
allowSet.add("Grep");
allowSet.add("Glob");
allowSet.add("LS");
if (webSearchEnabled) {
  allowSet.add("WebSearch");
}
settings.permissions.allow = Array.from(allowSet);

if (!settings.permissions.defaultMode || typeof settings.permissions.defaultMode !== "string") {
  settings.permissions.defaultMode = "default";
}

if (typeof desiredLanguage === "string" && desiredLanguage.length > 0) {
  settings.language = desiredLanguage;
}

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
NODE

  info "Synced Claude defaults: ${CLAUDE_SETTINGS}"
}

sync_gemini_manifest() {
  ensure_parent_dir "${GEMINI_MCP_MANAGED}"
  backup_file "${GEMINI_MCP_MANAGED}"

  node - "${EFFECTIVE_REGISTRY}" "${GEMINI_MCP_MANAGED}" <<'NODE'
const fs = require("fs");
const registryPath = process.argv[2];
const outPath = process.argv[3];

const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const servers = registry.servers || {};
const projects = registry.projects || {};
const defaults = registry.defaults || {};

function targetEnabled(server, target) {
  if (!server || typeof server !== "object") return false;
  if (server.enabled === false) return false;
  if (server.delivery && server.delivery[target] === "disabled") return false;
  const targets = server.targets;
  if (!Array.isArray(targets) || targets.length === 0) return true;
  return targets.includes(target);
}

function resolveScoped(obj, key, fallback) {
  if (!obj || typeof obj !== "object") return fallback;
  const v = obj[key];
  if (typeof v === "string" || typeof v === "boolean") return v;
  if (v && typeof v === "object") {
    if (typeof v.gemini === "string" || typeof v.gemini === "boolean") return v.gemini;
    if (typeof v.default === "string" || typeof v.default === "boolean") return v.default;
  }
  return fallback;
}

const geminiServers = {};
for (const [name, cfg] of Object.entries(servers)) {
  if (targetEnabled(cfg, "gemini")) geminiServers[name] = cfg;
}

const outBase = {
  managedBy: "update-ai-clis.sh",
  note: "Gemini CLI managed manifest (settings + metadata).",
  preferredLanguage: resolveScoped(defaults, "language", "日本語"),
  webSearchPreferred: resolveScoped(defaults, "webSearch", true),
  servers: geminiServers,
  projects
};

let generatedAt = new Date().toISOString();
if (fs.existsSync(outPath)) {
  try {
    const prev = JSON.parse(fs.readFileSync(outPath, "utf8"));
    if (prev && typeof prev === "object" && typeof prev.generatedAt === "string") {
      const prevComparable = { ...prev };
      delete prevComparable.generatedAt;
      if (JSON.stringify(prevComparable) === JSON.stringify(outBase)) {
        generatedAt = prev.generatedAt;
      }
    }
  } catch {
    // Ignore parse errors; regenerate managed manifest.
  }
}

const out = {
  ...outBase,
  generatedAt
};

fs.writeFileSync(outPath, JSON.stringify(out, null, 2) + "\n");
NODE

  info "Synced Gemini managed manifest: ${GEMINI_MCP_MANAGED}"
}

sync_gemini_settings_baseline() {
  ensure_parent_dir "${GEMINI_SETTINGS}"
  backup_file "${GEMINI_SETTINGS}"

  local gemini_count
  gemini_count="$(node - "${EFFECTIVE_REGISTRY}" "${GEMINI_SETTINGS}" <<'NODE'
const fs = require("fs");
const registryPath = process.argv[2];
const settingsPath = process.argv[3];

const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const servers = registry.servers || {};

function isObject(v) {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function targetEnabled(server, target) {
  if (!isObject(server)) return false;
  if (server.enabled === false) return false;
  if (isObject(server.delivery) && server.delivery[target] === "disabled") return false;
  const targets = server.targets;
  if (!Array.isArray(targets) || targets.length === 0) return true;
  return targets.includes(target);
}

function resolveEnvValue(value) {
  if (typeof value !== "string") return String(value ?? "");
  const match = value.match(/^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$/);
  if (!match) return value;
  return process.env[match[1]] || "";
}

function toStringArray(v) {
  if (!Array.isArray(v)) return [];
  return v.map((x) => String(x));
}

function buildServer(cfg) {
  if (!targetEnabled(cfg, "gemini")) return null;

  const isHttpType = cfg && (cfg.type === "http" || cfg.type === "sse");
  const httpUrl = typeof cfg?.httpUrl === "string" && cfg.httpUrl.length > 0
    ? cfg.httpUrl
    : (typeof cfg?.url === "string" && cfg.url.length > 0 ? cfg.url : "");
  if (isHttpType || httpUrl.length > 0) {
    if (httpUrl.length === 0) return null;
    const out = {
      httpUrl
    };
    if (typeof cfg.type === "string") out.type = cfg.type;
    if (isObject(cfg.headers)) out.headers = cfg.headers;
    if (typeof cfg.timeout === "number") out.timeout = cfg.timeout;
    if (typeof cfg.trust === "boolean") out.trust = cfg.trust;
    if (Array.isArray(cfg.includeTools)) out.includeTools = toStringArray(cfg.includeTools);
    if (Array.isArray(cfg.excludeTools)) out.excludeTools = toStringArray(cfg.excludeTools);
    return out;
  }

  if (typeof cfg?.command !== "string" || cfg.command.length === 0) return null;
  const out = {
    command: cfg.command
  };
  const args = toStringArray(cfg.args);
  if (args.length > 0) out.args = args;
  if (typeof cfg.cwd === "string" && cfg.cwd.length > 0) out.cwd = cfg.cwd;
  if (typeof cfg.timeout === "number") out.timeout = cfg.timeout;
  if (typeof cfg.trust === "boolean") out.trust = cfg.trust;
  if (Array.isArray(cfg.includeTools)) out.includeTools = toStringArray(cfg.includeTools);
  if (Array.isArray(cfg.excludeTools)) out.excludeTools = toStringArray(cfg.excludeTools);

  const env = isObject(cfg.env) ? cfg.env : {};
  const resolvedEnv = {};
  for (const [k, v] of Object.entries(env)) {
    const resolved = resolveEnvValue(v);
    if (resolved.length > 0) resolvedEnv[k] = resolved;
  }
  if (Object.keys(resolvedEnv).length > 0) out.env = resolvedEnv;
  return out;
}

let settings = {};
if (fs.existsSync(settingsPath)) {
  try {
    const loaded = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
    if (isObject(loaded)) settings = loaded;
  } catch {
    settings = {};
  }
}

if (typeof settings.selectedAuthType !== "string" || settings.selectedAuthType.length === 0) {
  settings.selectedAuthType = "oauth-personal";
}

const mcpServers = {};
for (const name of Object.keys(servers).sort()) {
  const built = buildServer(servers[name]);
  if (built) mcpServers[name] = built;
}
settings.mcpServers = mcpServers;

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
process.stdout.write(String(Object.keys(mcpServers).length));
NODE
)"

  info "Synced Gemini settings: ${GEMINI_SETTINGS} (active servers: ${gemini_count})"
}

sync_all() {
  ensure_node
  build_effective_registry "${ACTIVE_PROJECT_REF}"
  local layers="${EFFECTIVE_LAYERS}"

  info "Applying unified config layers: ${layers}"

  sync_codex_mcp
  ensure_codex_web_search_default
  info "Synced Codex defaults: web_search = true"

  local claude_count
  claude_count="$(sync_claude_mcp)"
  info "Synced Claude MCP config: ${CLAUDE_JSON} (active servers: ${claude_count})"
  sync_claude_settings_defaults

  sync_gemini_settings_baseline
  sync_gemini_manifest
  sync_skills
  sync_global_instructions

  info "Backup snapshot: ${BACKUP_DIR}"
}

clear_claude_mcp() {
  ensure_parent_dir "${CLAUDE_JSON}"
  backup_file "${CLAUDE_JSON}"

  node - "${CLAUDE_JSON}" <<'NODE'
const fs = require("fs");
const claudePath = process.argv[2];
let claude = {};
if (fs.existsSync(claudePath)) {
  try {
    claude = JSON.parse(fs.readFileSync(claudePath, "utf8"));
  } catch {
    claude = {};
  }
}
if (!claude.projects || typeof claude.projects !== "object" || Array.isArray(claude.projects)) {
  claude.projects = {};
}
claude.mcpServers = {};
for (const projectValue of Object.values(claude.projects)) {
  if (projectValue && typeof projectValue === "object" && !Array.isArray(projectValue)) {
    projectValue.mcpServers = {};
    projectValue.mcpContextUris = [];
  }
}
fs.writeFileSync(claudePath, JSON.stringify(claude, null, 2) + "\n");
NODE
  info "Reset Claude MCP config: ${CLAUDE_JSON}"
}

reset_codex_to_baseline() {
  ensure_codex_base_file
  ensure_parent_dir "${CODEX_TOML}"
  backup_file "${CODEX_TOML}"

  cp "${CODEX_BASE_FILE}" "${CODEX_TOML}"

  ensure_codex_web_search_default
  chmod 600 "${CODEX_TOML}" 2>/dev/null || true
  info "Reset Codex config to baseline: ${CODEX_TOML}"
}

reset_gemini_settings() {
  ensure_parent_dir "${GEMINI_SETTINGS}"
  backup_file "${GEMINI_SETTINGS}"
  backup_file "${GEMINI_MCP_MANAGED}"

  sync_gemini_settings_baseline
  rm -f "${GEMINI_MCP_MANAGED}"
  info "Reset Gemini settings baseline: ${GEMINI_SETTINGS}"
}

collect_uninstall_list() {
  local mode="$1" # npm|pipx
  node - "${EFFECTIVE_REGISTRY}" "${mode}" <<'NODE'
const fs = require("fs");
const registryPath = process.argv[2];
const mode = process.argv[3];
const reg = JSON.parse(fs.readFileSync(registryPath, "utf8"));
const set = new Set();

const uninstall = reg.uninstall && typeof reg.uninstall === "object" ? reg.uninstall : {};
const list = uninstall[mode];
if (Array.isArray(list)) {
  for (const v of list) {
    if (typeof v === "string" && v.length > 0) set.add(v);
  }
}

const servers = reg.servers && typeof reg.servers === "object" ? reg.servers : {};
for (const cfg of Object.values(servers)) {
  if (!cfg || typeof cfg !== "object") continue;
  if (mode === "npm" && typeof cfg.npm_package === "string" && cfg.npm_package.length > 0) {
    set.add(cfg.npm_package);
  }
  if (mode === "pipx" && typeof cfg.pipx_package === "string" && cfg.pipx_package.length > 0) {
    set.add(cfg.pipx_package);
  }
}

for (const item of [...set].sort()) {
  console.log(item);
}
NODE
}

uninstall_npm_mcp_packages() {
  local npm_packages=()
  mapfile -t npm_packages < <(collect_uninstall_list "npm")
  if [[ "${#npm_packages[@]}" -eq 0 ]]; then
    info "No npm MCP packages registered for uninstall."
    return
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: npm uninstall -g ${npm_packages[*]}"
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    warn "npm not found; skip npm MCP uninstall."
    return
  fi

  if npm uninstall -g "${npm_packages[@]}" >/dev/null 2>&1; then
    info "Removed npm MCP packages: ${npm_packages[*]}"
  else
    warn "Failed to remove npm MCP packages. Run with enough permissions if needed:"
    warn "npm uninstall -g ${npm_packages[*]}"
  fi
}

uninstall_pipx_mcp_packages() {
  local pipx_packages=()
  mapfile -t pipx_packages < <(collect_uninstall_list "pipx")
  if [[ "${#pipx_packages[@]}" -eq 0 ]]; then
    info "No pipx MCP packages registered for uninstall."
    return
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: pipx uninstall <each> ${pipx_packages[*]}"
    return
  fi

  if ! command -v pipx >/dev/null 2>&1; then
    warn "pipx not found; skip pipx MCP uninstall."
    return
  fi

  local removed_any=0
  local pkg
  for pkg in "${pipx_packages[@]}"; do
    if pipx list 2>/dev/null | grep -q "package ${pkg} "; then
      if pipx uninstall "${pkg}" >/dev/null 2>&1; then
        info "Removed pipx MCP package: ${pkg}"
        removed_any=1
      else
        warn "Failed to remove pipx package: ${pkg}"
      fi
    fi
  done
  if [[ "${removed_any}" -eq 0 ]]; then
    info "No installed pipx MCP packages found in registry."
  fi
}

reset_all() {
  ensure_node
  build_effective_registry "${ACTIVE_PROJECT_REF}"

  info "Running unified reset (preserving auth tokens)."
  reset_codex_to_baseline
  clear_claude_mcp
  sync_claude_settings_defaults
  reset_gemini_settings
  sync_skills
  sync_global_instructions
  uninstall_npm_mcp_packages
  uninstall_pipx_mcp_packages
  info "Backup snapshot: ${BACKUP_DIR}"
}

status() {
  ensure_node
  build_effective_registry "${ACTIVE_PROJECT_REF}"
  local layers="${EFFECTIVE_LAYERS}"

  show_versions
  divider
  printf "  %-24s %s\n" "Active layers:" "${layers}"

  local codex_count="0"
  if [[ -f "${CODEX_TOML}" ]]; then
    codex_count="$(grep -nE '^[[:space:]]*\[mcp_servers(\.|])' "${CODEX_TOML}" 2>/dev/null | wc -l | tr -d ' ')"
  fi
  printf "  %-24s %s\n" "Codex mcp_servers:" "${codex_count}"

  local codex_web="off"
  if [[ -f "${CODEX_TOML}" ]] && grep -qE '^[[:space:]]*web_search[[:space:]]*=[[:space:]]*true' "${CODEX_TOML}"; then
    codex_web="on"
  fi
  printf "  %-24s %s\n" "Codex web_search:" "${codex_web}"

  local claude_total="0"
  if [[ -f "${CLAUDE_JSON}" ]]; then
    claude_total="$(node - "${CLAUDE_JSON}" <<'NODE'
const fs = require("fs");
const p = process.argv[2];
try {
  const j = JSON.parse(fs.readFileSync(p, "utf8"));
  const globalCount = Object.keys(j.mcpServers || {}).length;
  const projects = j.projects || {};
  const projCount = Object.values(projects).reduce((acc, v) => acc + Object.keys((v && v.mcpServers) || {}).length, 0);
  process.stdout.write(String(globalCount + projCount));
} catch {
  process.stdout.write("0");
}
NODE
)"
  fi
  printf "  %-24s %s\n" "Claude mcpServers:" "${claude_total}"

  local claude_web="off"
  if [[ -f "${CLAUDE_SETTINGS}" ]] && grep -q '"WebSearch"' "${CLAUDE_SETTINGS}"; then
    claude_web="on"
  fi
  printf "  %-24s %s\n" "Claude WebSearch allow:" "${claude_web}"

  if [[ -f "${GEMINI_MCP_MANAGED}" ]]; then
    printf "  %-24s %s\n" "Gemini manifest:" "${GEMINI_MCP_MANAGED}"
  else
    printf "  %-24s %s\n" "Gemini manifest:" "not present"
  fi

  local gemini_count="0"
  if [[ -f "${GEMINI_SETTINGS}" ]]; then
    gemini_count="$(node - "${GEMINI_SETTINGS}" <<'NODE'
const fs = require("fs");
const p = process.argv[2];
try {
  const j = JSON.parse(fs.readFileSync(p, "utf8"));
  process.stdout.write(String(Object.keys(j.mcpServers || {}).length));
} catch {
  process.stdout.write("0");
}
NODE
)"
  fi
  printf "  %-24s %s\n" "Gemini mcpServers:" "${gemini_count}"

  local enabled_count
  enabled_count="$(node - "${EFFECTIVE_REGISTRY}" <<'NODE'
const fs = require("fs");
const p = process.argv[2];
const j = JSON.parse(fs.readFileSync(p, "utf8"));
const servers = j.servers || {};
const n = Object.values(servers).filter(v => v && v.enabled !== false).length;
process.stdout.write(String(n));
NODE
)"
  printf "  %-24s %s\n" "Registry enabled MCP:" "${enabled_count}"

  local master_skill_count
  local claude_skill_count
  local gemini_skill_count
  local codex_skill_count
  master_skill_count="$(count_skills_in_dir "${SKILLS_MASTER_DIR}")"
  claude_skill_count="$(count_skills_in_dir "${CLAUDE_SKILLS_DIR}")"
  gemini_skill_count="$(count_skills_in_dir "${GEMINI_SKILLS_DIR}")"
  codex_skill_count="$(count_skills_in_dir "${CODEX_SKILLS_DIR}")"
  local master_hash
  master_hash="$(dir_content_hash "${SKILLS_MASTER_DIR}" | cut -c1-12)"
  local claude_hash
  claude_hash="$(dir_content_hash "${CLAUDE_SKILLS_DIR}" | cut -c1-12)"
  printf "  %-24s %s (hash:%s)\n" "Skills master:" "${master_skill_count}" "${master_hash}"
  printf "  %-24s %s (hash:%s)\n" "Claude skills:" "${claude_skill_count}" "${claude_hash}"
  printf "  %-24s %s\n" "Gemini skills:" "${gemini_skill_count}"
  printf "  %-24s %s\n" "Codex skills:" "${codex_skill_count}"

  if [[ -f "${GLOBAL_INSTRUCTIONS}" ]]; then
    local instr_hash
    instr_hash="$(sha256_short "${GLOBAL_INSTRUCTIONS}")"
    local layers_info="${instr_hash}"
    if [[ -n "${ACTIVE_PROJECT_REF}" ]]; then
      local _pn=""
      if [[ -d "${ACTIVE_PROJECT_REF}" ]]; then _pn="$(basename "${ACTIVE_PROJECT_REF}")"; else _pn="${ACTIVE_PROJECT_REF}"; fi
      if [[ -f "${PROJECTS_DIR}/${_pn}.instructions.md" ]]; then
        layers_info="${layers_info}+project"
      fi
    fi
    if [[ -f "${GLOBAL_INSTRUCTIONS_LOCAL}" ]]; then
      layers_info="${layers_info}+local"
    fi
    printf "  %-24s %s\n" "Global instructions:" "present (hash:${layers_info})"
  else
    printf "  %-24s %s\n" "Global instructions:" "not configured"
  fi
}

check_drift() {
  ensure_node
  build_effective_registry "${ACTIVE_PROJECT_REF}"

  local drift=0

  check_file_match() {
    local label="$1" expected="$2" actual="$3"
    if [[ ! -e "${expected}" && ! -e "${actual}" ]]; then
      return 0
    fi
    if [[ ! -e "${expected}" ]]; then
      warn "Drift: ${label} exists but has no expected source"
      drift=1
      return 0
    fi
    if [[ ! -e "${actual}" ]]; then
      warn "Drift: ${label} missing (expected from source)"
      drift=1
      return 0
    fi
    if ! cmp -s "${expected}" "${actual}"; then
      warn "Drift: ${label} content mismatch"
      drift=1
    fi
  }

  check_skills_match() {
    local label="$1" target_dir="$2"
    if [[ ! -d "${target_dir}" ]]; then
      if [[ "$(count_skills_in_dir "${SKILLS_MASTER_DIR}")" -gt 0 ]]; then
        warn "Drift: ${label} skills directory missing"
        drift=1
      fi
      return 0
    fi
    local tmp_rendered
    tmp_rendered="$(mktemp -d)"
    local skill_name src_dir dst_dir
    while IFS= read -r skill_name; do
      [[ -n "${skill_name}" ]] || continue
      src_dir="${SKILLS_MASTER_DIR}/${skill_name}"
      dst_dir="${tmp_rendered}/${skill_name}"
      mkdir -p "${dst_dir}"
      cp -a "${src_dir}/." "${dst_dir}/"
      render_skill_for_target "${dst_dir}/SKILL.md" "${target_dir}"
    done < <(list_master_skill_names | sort)
    local skill_name_check
    while IFS= read -r skill_name_check; do
      [[ -n "${skill_name_check}" ]] || continue
      local exp_skill="${tmp_rendered}/${skill_name_check}/SKILL.md"
      local act_skill="${target_dir}/${skill_name_check}/SKILL.md"
      if [[ ! -f "${act_skill}" ]]; then
        warn "Drift: ${label} skill '${skill_name_check}' missing"
        drift=1
      elif ! cmp -s "${exp_skill}" "${act_skill}"; then
        warn "Drift: ${label} skill '${skill_name_check}' content mismatch"
        drift=1
      fi
    done < <(list_master_skill_names | sort)
    rm -rf "${tmp_rendered}"
  }

  local merged_instructions
  merged_instructions="$(build_merged_instructions)"

  if [[ -n "${merged_instructions}" ]]; then
    check_file_match "CLAUDE.md" "${merged_instructions}" "${HOME}/.claude/CLAUDE.md"
    check_file_match "AGENTS.md" "${merged_instructions}" "${HOME}/.codex/AGENTS.md"
    check_file_match "GEMINI.md" "${merged_instructions}" "${HOME}/.gemini/GEMINI.md"
    rm -f "${merged_instructions}"
  fi

  check_skills_match "Claude" "${CLAUDE_SKILLS_DIR}"
  check_skills_match "Gemini" "${GEMINI_SKILLS_DIR}"
  check_skills_match "Codex" "${CODEX_SKILLS_DIR}"

  if [[ "${drift}" -eq 0 ]]; then
    info "Check passed: no drift detected."
  else
    error "Check failed: drift detected. Run 'sync' to fix."
    return 1
  fi
}

seed_preview_file() {
  local src="$1"
  local dst="$2"
  ensure_parent_dir "${dst}"
  if [[ -e "${src}" ]]; then
    cp -a "${src}" "${dst}"
  else
    rm -f "${dst}"
  fi
}

show_diff_for_file() {
  local current_file="$1"
  local next_file="$2"
  local label="$3"

  if [[ ! -e "${current_file}" && ! -e "${next_file}" ]]; then
    return 0
  fi

  if [[ -e "${current_file}" && -e "${next_file}" ]] && cmp -s "${current_file}" "${next_file}"; then
    printf "  %-24s %s\n" "${label}:" "no change"
    return 0
  fi

  divider
  info "Diff: ${label}"
  local left="${current_file}"
  local right="${next_file}"
  if [[ ! -e "${left}" ]]; then
    left="/dev/null"
  fi
  if [[ ! -e "${right}" ]]; then
    right="/dev/null"
  fi
  diff -u --label "${label} (current)" --label "${label} (next)" "${left}" "${right}" || true
}

preview_sync_diff() {
  local preview_root
  preview_root="$(mktemp -d)"

  local original_claude_json="${CLAUDE_JSON}"
  local original_claude_settings="${CLAUDE_SETTINGS}"
  local original_codex_toml="${CODEX_TOML}"
  local original_gemini_settings="${GEMINI_SETTINGS}"
  local original_gemini_manifest="${GEMINI_MCP_MANAGED}"

  local CLAUDE_JSON="${preview_root}/.claude.json"
  local CLAUDE_SETTINGS="${preview_root}/.claude/settings.json"
  local CODEX_TOML="${preview_root}/.codex/config.toml"
  local GEMINI_SETTINGS="${preview_root}/.gemini/settings.json"
  local GEMINI_MCP_MANAGED="${preview_root}/.gemini/mcp.managed.json"
  local BACKUP_DIR="${preview_root}/backups"
  local DRY_RUN=1

  seed_preview_file "${original_claude_json}" "${CLAUDE_JSON}"
  seed_preview_file "${original_claude_settings}" "${CLAUDE_SETTINGS}"
  seed_preview_file "${original_codex_toml}" "${CODEX_TOML}"
  seed_preview_file "${original_gemini_settings}" "${GEMINI_SETTINGS}"
  seed_preview_file "${original_gemini_manifest}" "${GEMINI_MCP_MANAGED}"

  sync_all

  divider
  info "Dry-run diff summary (sync):"
  show_diff_for_file "${original_claude_json}" "${CLAUDE_JSON}" "~/.claude.json"
  show_diff_for_file "${original_claude_settings}" "${CLAUDE_SETTINGS}" "~/.claude/settings.json"
  show_diff_for_file "${original_codex_toml}" "${CODEX_TOML}" "~/.codex/config.toml"
  show_diff_for_file "${original_gemini_settings}" "${GEMINI_SETTINGS}" "~/.gemini/settings.json"
  show_diff_for_file "${original_gemini_manifest}" "${GEMINI_MCP_MANAGED}" "~/.gemini/mcp.managed.json"

  rm -rf "${preview_root}"
}

preview_reset_diff() {
  local preview_root
  preview_root="$(mktemp -d)"

  local original_claude_json="${CLAUDE_JSON}"
  local original_claude_settings="${CLAUDE_SETTINGS}"
  local original_codex_toml="${CODEX_TOML}"
  local original_gemini_settings="${GEMINI_SETTINGS}"
  local original_gemini_manifest="${GEMINI_MCP_MANAGED}"

  local CLAUDE_JSON="${preview_root}/.claude.json"
  local CLAUDE_SETTINGS="${preview_root}/.claude/settings.json"
  local CODEX_TOML="${preview_root}/.codex/config.toml"
  local GEMINI_SETTINGS="${preview_root}/.gemini/settings.json"
  local GEMINI_MCP_MANAGED="${preview_root}/.gemini/mcp.managed.json"
  local BACKUP_DIR="${preview_root}/backups"
  local DRY_RUN=1

  seed_preview_file "${original_claude_json}" "${CLAUDE_JSON}"
  seed_preview_file "${original_claude_settings}" "${CLAUDE_SETTINGS}"
  seed_preview_file "${original_codex_toml}" "${CODEX_TOML}"
  seed_preview_file "${original_gemini_settings}" "${GEMINI_SETTINGS}"
  seed_preview_file "${original_gemini_manifest}" "${GEMINI_MCP_MANAGED}"

  reset_all

  divider
  info "Dry-run diff summary (reset):"
  show_diff_for_file "${original_claude_json}" "${CLAUDE_JSON}" "~/.claude.json"
  show_diff_for_file "${original_claude_settings}" "${CLAUDE_SETTINGS}" "~/.claude/settings.json"
  show_diff_for_file "${original_codex_toml}" "${CODEX_TOML}" "~/.codex/config.toml"
  show_diff_for_file "${original_gemini_settings}" "${GEMINI_SETTINGS}" "~/.gemini/settings.json"
  show_diff_for_file "${original_gemini_manifest}" "${GEMINI_MCP_MANAGED}" "~/.gemini/mcp.managed.json"

  rm -rf "${preview_root}"
}

main() {
  local cmd="update"
  if [[ $# -gt 0 ]]; then
    cmd="$1"
    shift
  fi

  local project_ref=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      *)
        if [[ -z "${project_ref}" ]]; then
          project_ref="$1"
        else
          error "Too many arguments: ${project_ref} ${1}"
          usage
          exit 1
        fi
        ;;
    esac
    shift
  done
  ACTIVE_PROJECT_REF="${project_ref}"

  case "${cmd}" in
    init)
      bootstrap_config_files
      ;;
    lock-base)
      bootstrap_config_files
      write_base_lock
      info "Locked base registry: ${BASE_REGISTRY_FILE}"
      info "Updated lock hash: ${BASE_LOCK_FILE}"
      ;;
    project-init)
      project_init "${project_ref}"
      ;;
    update)
      update_clis
      ;;
    sync)
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        preview_sync_diff
      else
        sync_all
      fi
      ;;
    sync-here)
      assert_not_setupscript_dir "${PWD}"
      ACTIVE_PROJECT_REF="${PWD}"
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        preview_sync_diff
      else
        sync_all
      fi
      ;;
    reset)
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        preview_reset_diff
      else
        reset_all
      fi
      ;;
    reset-here)
      assert_not_setupscript_dir "${PWD}"
      ACTIVE_PROJECT_REF="${PWD}"
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        preview_reset_diff
      else
        reset_all
      fi
      ;;
    all)
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        update_clis
        divider
        preview_sync_diff
      else
        update_clis
        divider
        sync_all
      fi
      ;;
    all-here)
      assert_not_setupscript_dir "${PWD}"
      ACTIVE_PROJECT_REF="${PWD}"
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        update_clis
        divider
        preview_sync_diff
      else
        update_clis
        divider
        sync_all
      fi
      ;;
    status)
      status
      ;;
    diff)
      preview_sync_diff
      ;;
    check)
      check_drift
      ;;
    status-here)
      assert_not_setupscript_dir "${PWD}"
      ACTIVE_PROJECT_REF="${PWD}"
      status
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      error "Unknown command: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

main "$@"
