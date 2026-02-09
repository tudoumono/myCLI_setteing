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
PROJECT_LOCAL_FILE_NAME=".ai-stack.local.json"
PROJECT_LOCAL_INSTRUCTIONS_FILE_NAME=".ai-stack.instructions.md"
CODEX_BASE_FILE="${CONFIG_DIR}/codex-base.toml"
SKILLS_MASTER_DIR="${CONFIG_DIR}/skills"
AGENTS_MASTER_DIR="${CONFIG_DIR}/agents"
GLOBAL_INSTRUCTIONS="${CONFIG_DIR}/global-instructions.md"
GLOBAL_INSTRUCTIONS_LOCAL="${CONFIG_DIR}/global-instructions.local.md"

CLAUDE_JSON="${HOME}/.claude.json"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
CODEX_TOML="${HOME}/.codex/config.toml"
GEMINI_SETTINGS="${HOME}/.gemini/settings.json"
GEMINI_MCP_MANAGED="${HOME}/.gemini/mcp.managed.json"
CLAUDE_SKILLS_DIR="${HOME}/.claude/skills"
CLAUDE_AGENTS_DIR="${HOME}/.claude/agents"
GEMINI_SKILLS_DIR="${HOME}/.gemini/skills"
CODEX_SKILLS_DIR="${HOME}/.codex/skills"
GEMINI_AGENTS_DIR="${HOME}/.gemini/agents"
CODEX_AGENTS_DIR="${HOME}/.codex/agents"

RUN_TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${CONFIG_DIR}/backups/${RUN_TS}"

EFFECTIVE_REGISTRY=""
EFFECTIVE_LAYERS=""
ACTIVE_PROJECT_REF=""
DRY_RUN=0

# Disable ANSI colors when output is not a TTY (e.g. menu log, CI) or NO_COLOR is set.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  NC='\033[0m'
else
  GREEN=''
  YELLOW=''
  RED=''
  NC=''
fi

info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
divider() { printf '%s\n' "------------------------------------------"; }

usage() {
  cat <<'USAGE_EOF'
使い方:
  ./update-ai-clis.sh init
  ./update-ai-clis.sh lock-base
  ./update-ai-clis.sh project-init [project_dir]
  ./update-ai-clis.sh update
  ./update-ai-clis.sh sync [project]
  ./update-ai-clis.sh sync-here
  ./update-ai-clis.sh promote [project]
  ./update-ai-clis.sh promote-here
  ./update-ai-clis.sh reset [project]
  ./update-ai-clis.sh reset-here
  ./update-ai-clis.sh all [project]
  ./update-ai-clis.sh all-here
  ./update-ai-clis.sh diff [project]
  ./update-ai-clis.sh check [project]
  ./update-ai-clis.sh status [project]
  ./update-ai-clis.sh status-here
  ./update-ai-clis.sh skill-share <skill_name>
  ./update-ai-clis.sh skill-promote <skill_name|skill_dir>
  ./update-ai-clis.sh skill-share-all
  ./update-ai-clis.sh wipe-user
  ./update-ai-clis.sh reset-user
  ./update-ai-clis.sh -h
  ./update-ai-clis.sh help
  ./update-ai-clis.sh --help
  ./update-ai-clis.sh update --dry-run
  ./update-ai-clis.sh <sync|promote|reset|all> [project] --dry-run
  ./update-ai-clis.sh <sync-here|promote-here|reset-here|all-here> --dry-run
  ./update-ai-clis.sh <skill-share|skill-promote|skill-share-all> --dry-run
  ./update-ai-clis.sh <wipe-user|reset-user> --dry-run

コマンド説明:
  init    ai-config/ 配下のベースファイルを作成し、ユーザ設定へ反映します（setupScript フォルダでのみ実行可能）。
  lock-base  base.json のハッシュロックを更新します（意図したベース更新時のみ。setupScript フォルダでのみ実行可能）。
  project-init  現在ディレクトリ（または指定パス）にPJ管理用ファイルを初期化し、差分を表示します。
  update  Claude/Gemini/Codex CLI を npm 経由で更新します。
  sync    ユーザ設定差分を検出し、差分があれば共通設定へ揃えます（PJ文脈では ~/ 配下へ反映しません）。
  sync-here  project = 現在ディレクトリとして差分確認を実行します（~/ 配下へ反映しません）。
  promote  統合設定を ~/ 配下の各CLI設定へ反映します（昇格）。
  promote-here  project = 現在ディレクトリとして昇格を実行します。
  reset   ベース状態へ戻します（MCP設定のクリア + 登録済みMCPパッケージのアンインストール）。
  reset-here  project = 現在ディレクトリとして reset を実行します。
  all     update の後に sync を実行します。
  all-here  project = 現在ディレクトリとして all を実行します。
  diff    sync 実行時にどう変わるかを実ファイル変更なしで表示します。
  check   skills / agents / global instructions のドリフトを検査し、不一致時は非0で終了します（CI向け）。
  status  バージョン情報と有効設定状態を表示します。
  status-here  project = 現在ディレクトリとして status を表示します。
  skill-share  指定したローカルスキルを 3CLI 間で共有します（managed skill は対象外）。
  skill-promote  PJで作成したスキル（名前またはディレクトリ）を3CLIのユーザ設定へ昇格します。
  skill-share-all  ローカルスキル（managed 以外）を 3CLI 間で一括共有します。
  wipe-user  ユーザ設定を完全に削除します（git設定反映も含めて空にする）。
  reset-user  ユーザ設定をgit管理の設定へ戻します（initと同等）。
  --dry-run  update/sync/promote/reset/all（*-here 含む）と skill-share 系、wipe/reset-user を実変更なしでプレビューします。

レイヤー優先順（後ろほど優先）:
  1) ai-config/base.json               （グローバル）
  2) ai-config/projects/<project>.json （レガシーPJ差分、任意）
  3) ai-config/local.json              （マシンローカル、任意）
  4) <project>/.ai-stack.local.json    （PJローカル、任意・コミット可）
  
補足:
  - `<project>/.ai-stack.local.json` で `projectServers: ["name"]` を指定すると、
    実行中プロジェクトの絶対パスへ自動マッピングされます（絶対パスをJSONへ直書き不要）。
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
web_search = "live"

[projects."/root"]
trust_level = "trusted"

[features]
shell_snapshot = true
collab = true
apps = true
EOF_CODEX_BASE
}

ensure_codex_base_file() {
  local allow_create="${1:-no}" # yes|no
  if [[ ! -f "${CODEX_BASE_FILE}" ]]; then
    if [[ "${allow_create}" == "yes" ]]; then
      ensure_parent_dir "${CODEX_BASE_FILE}"
      write_codex_base_template "${CODEX_BASE_FILE}"
      info "Created Codex baseline: ${CODEX_BASE_FILE}"
    else
      error "Codex baseline file missing: ${CODEX_BASE_FILE}"
      error "Run './update-ai-clis.sh init' from setupScript directory first."
      exit 1
    fi
  fi
}

escape_sed_replacement() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/[&|]/\\&/g'
}

ensure_skills_master() {
  local allow_create="${1:-no}" # yes|no

  if [[ ! -d "${SKILLS_MASTER_DIR}" ]]; then
    if [[ "${allow_create}" == "yes" ]]; then
      mkdir -p "${SKILLS_MASTER_DIR}"
    else
      error "Skills master directory missing: ${SKILLS_MASTER_DIR}"
      error "Run './update-ai-clis.sh init' from setupScript directory first."
      exit 1
    fi
  fi

  if [[ ! -f "${SKILLS_MASTER_DIR}/README.md" ]]; then
    if [[ "${allow_create}" == "yes" ]]; then
      cat > "${SKILLS_MASTER_DIR}/README.md" <<'EOF_SKILLS_README'
# skills master

`ai-config/skills` is the single source of truth for user skills.

Synced targets:

- `~/.claude/skills`
- `~/.gemini/skills`
- `~/.codex/skills`
EOF_SKILLS_README
    else
      warn "Skills master README missing: ${SKILLS_MASTER_DIR}/README.md"
    fi
  fi
}

ensure_agents_master() {
  local allow_create="${1:-no}" # yes|no

  if [[ ! -d "${AGENTS_MASTER_DIR}" ]]; then
    if [[ "${allow_create}" == "yes" ]]; then
      mkdir -p "${AGENTS_MASTER_DIR}"
    else
      error "Agents master directory missing: ${AGENTS_MASTER_DIR}"
      error "Run './update-ai-clis.sh init' from setupScript directory first."
      exit 1
    fi
  fi

  if [[ ! -f "${AGENTS_MASTER_DIR}/README.md" ]]; then
    if [[ "${allow_create}" == "yes" ]]; then
      cat > "${AGENTS_MASTER_DIR}/README.md" <<'EOF_AGENTS_README'
# agents master

`ai-config/agents` is the single source of truth for custom agents.

Synced targets:

- `~/.claude/agents`
- `~/.gemini/agents`
- `~/.codex/agents`
EOF_AGENTS_README
    else
      warn "Agents master README missing: ${AGENTS_MASTER_DIR}/README.md"
    fi
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

list_master_agent_files() {
  [[ -d "${AGENTS_MASTER_DIR}" ]] || return 0
  find "${AGENTS_MASTER_DIR}" -mindepth 1 -type f \
    ! -name 'README.md' \
    ! -path '*/.*' \
    -print 2>/dev/null | sort
}

count_agent_files_in_dir() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    echo "0"
    return 0
  fi
  local count
  count="$(find "${dir}" -mindepth 1 -type f \
    ! -name 'README.md' \
    ! -name '.ai-stack.managed-agents' \
    ! -path '*/.*' 2>/dev/null | wc -l | tr -d ' ')"
  echo "${count:-0}"
}

agent_tree_hash() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    echo "n/a"
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#${dir}/}"
    printf "%s %s\n" "${rel}" "$(sha256_of_file "${f}")" >> "${tmp}"
  done < <(find "${dir}" -mindepth 1 -type f \
    ! -name 'README.md' \
    ! -name '.ai-stack.managed-agents' \
    ! -path '*/.*' \
    -print0 2>/dev/null | sort -z)

  if [[ ! -s "${tmp}" ]]; then
    rm -f "${tmp}"
    echo "empty"
    return 0
  fi

  sort "${tmp}" | sha256_of_stdin
  rm -f "${tmp}"
}

agents_dir_for_cli() {
  local cli="$1"
  case "${cli}" in
    claude) printf "%s\n" "${CLAUDE_AGENTS_DIR}" ;;
    gemini) printf "%s\n" "${GEMINI_AGENTS_DIR}" ;;
    codex) printf "%s\n" "${CODEX_AGENTS_DIR}" ;;
    *)
      error "Unknown CLI target: ${cli}"
      return 1
      ;;
  esac
}

sync_agents_to_target() {
  local target_dir="$1"
  local manifest="${target_dir}/.ai-stack.managed-agents"
  local tmp_manifest
  tmp_manifest="$(mktemp)"
  mkdir -p "${target_dir}"

  local src rel dst
  while IFS= read -r src; do
    [[ -n "${src}" ]] || continue
    rel="${src#${AGENTS_MASTER_DIR}/}"
    dst="${target_dir}/${rel}"
    mkdir -p "$(dirname "${dst}")"
    rm -f "${dst}"
    cp -a "${src}" "${dst}"
    printf "%s\n" "${rel}" >> "${tmp_manifest}"
  done < <(list_master_agent_files)

  if [[ -f "${manifest}" ]]; then
    local stale
    while IFS= read -r stale; do
      [[ -n "${stale}" ]] || continue
      if ! grep -qFx "${stale}" "${tmp_manifest}" 2>/dev/null; then
        rm -f "${target_dir}/${stale}"
      fi
    done < "${manifest}"
  fi

  find "${target_dir}" -depth -type d -empty ! -path "${target_dir}" -delete 2>/dev/null || true
  mv "${tmp_manifest}" "${manifest}"
  chmod 644 "${manifest}" 2>/dev/null || true
}

sync_agents() {
  ensure_agents_master

  local master_count
  master_count="$(count_agent_files_in_dir "${AGENTS_MASTER_DIR}")"
  if [[ "${master_count}" -eq 0 ]]; then
    warn "No master agents found in ${AGENTS_MASTER_DIR}; skip agents sync."
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: skip agent distribution (master agents: ${master_count})."
    return 0
  fi

  local cli target_dir
  for cli in claude gemini codex; do
    target_dir="$(agents_dir_for_cli "${cli}")" || return 1
    sync_agents_to_target "${target_dir}"
  done
  info "Synced agents: master=${master_count}, targets=claude/gemini/codex"
}

skills_dir_for_cli() {
  local cli="$1"
  case "${cli}" in
    claude) printf "%s\n" "${CLAUDE_SKILLS_DIR}" ;;
    gemini) printf "%s\n" "${GEMINI_SKILLS_DIR}" ;;
    codex) printf "%s\n" "${CODEX_SKILLS_DIR}" ;;
    *)
      error "Unknown CLI target: ${cli}"
      return 1
      ;;
  esac
}

file_mtime_epoch() {
  local f="$1"
  if stat -c %Y "${f}" >/dev/null 2>&1; then
    stat -c %Y "${f}"
    return 0
  fi
  if stat -f %m "${f}" >/dev/null 2>&1; then
    stat -f %m "${f}"
    return 0
  fi
  printf "0\n"
}

list_skill_names_in_dir() {
  local dir="$1"
  [[ -d "${dir}" ]] || return 0
  local skill_dir
  local name
  while IFS= read -r -d '' skill_dir; do
    name="$(basename "${skill_dir}")"
    [[ "${name}" == .* ]] && continue
    [[ -f "${skill_dir}/SKILL.md" ]] || continue
    printf "%s\n" "${name}"
  done < <(find "${dir}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
}

share_skill_to_all_targets() {
  local skill_name="$1"
  local allow_managed="${2:-no}"

  if [[ -z "${skill_name}" ]]; then
    error "Skill name is required."
    return 1
  fi
  if [[ "${skill_name}" == *"/"* ]]; then
    error "Invalid skill name '${skill_name}'. Use only skill directory name."
    return 1
  fi

  if [[ "${allow_managed}" != "yes" && -f "${SKILLS_MASTER_DIR}/${skill_name}/SKILL.md" ]]; then
    error "Skill '${skill_name}' is managed by ai-config/skills."
    error "Use 'sync' to distribute managed skills."
    return 1
  fi

  local src_cli=""
  local src_skill_dir=""
  local src_mtime=-1
  local found_count=0
  local cli=""
  local target_dir=""
  local skill_md=""
  local mtime=0
  local hash=""
  local -A hashes=()

  for cli in claude gemini codex; do
    target_dir="$(skills_dir_for_cli "${cli}")" || return 1
    skill_md="${target_dir}/${skill_name}/SKILL.md"
    if [[ -f "${skill_md}" ]]; then
      found_count=$((found_count + 1))
      hash="$(sha256_of_file "${skill_md}")"
      hashes["${hash}"]=1
      mtime="$(file_mtime_epoch "${skill_md}")"
      if (( mtime > src_mtime )); then
        src_mtime="${mtime}"
        src_cli="${cli}"
        src_skill_dir="${target_dir}/${skill_name}"
      fi
    fi
  done

  if [[ "${found_count}" -eq 0 ]]; then
    error "Skill '${skill_name}' was not found in ~/.claude/skills, ~/.gemini/skills, ~/.codex/skills."
    return 1
  fi

  if [[ "${#hashes[@]}" -gt 1 ]]; then
    warn "Multiple variants found for '${skill_name}'."
    warn "Using latest modified copy from '${src_cli}' as source."
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: would share '${skill_name}' from ${src_cli} -> claude/gemini/codex"
    return 0
  fi

  local target_skill_dir=""
  for cli in claude gemini codex; do
    target_dir="$(skills_dir_for_cli "${cli}")" || return 1
    target_skill_dir="${target_dir}/${skill_name}"
    mkdir -p "${target_dir}"
    if [[ "${target_skill_dir}" != "${src_skill_dir}" ]]; then
      rm -rf "${target_skill_dir}"
      mkdir -p "${target_skill_dir}"
      cp -a "${src_skill_dir}/." "${target_skill_dir}/"
    fi
    render_skill_for_target "${target_skill_dir}/SKILL.md" "${target_dir}"
  done

  info "Shared local skill '${skill_name}' from ${src_cli} to claude/gemini/codex"
}

copy_skill_dir_to_all_targets() {
  local skill_dir="$1"
  local skill_name="$2"

  if [[ ! -f "${skill_dir}/SKILL.md" ]]; then
    error "SKILL.md not found: ${skill_dir}/SKILL.md"
    return 1
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: would promote '${skill_name}' from ${skill_dir} -> claude/gemini/codex"
    return 0
  fi

  local cli=""
  local target_dir=""
  local target_skill_dir=""
  for cli in claude gemini codex; do
    target_dir="$(skills_dir_for_cli "${cli}")" || return 1
    target_skill_dir="${target_dir}/${skill_name}"
    mkdir -p "${target_dir}"
    rm -rf "${target_skill_dir}"
    mkdir -p "${target_skill_dir}"
    cp -a "${skill_dir}/." "${target_skill_dir}/"
    render_skill_for_target "${target_skill_dir}/SKILL.md" "${target_dir}"
  done

  info "Promoted skill '${skill_name}' to claude/gemini/codex user settings."
}

skill_share() {
  local skill_name="${1:-}"
  if [[ -z "${skill_name}" ]]; then
    error "Usage: ./update-ai-clis.sh skill-share <skill_name>"
    exit 1
  fi
  bootstrap_config_files "verify"
  validate_base_locked
  share_skill_to_all_targets "${skill_name}"
}

skill_promote() {
  local skill_ref="${1:-}"
  if [[ -z "${skill_ref}" ]]; then
    error "Usage: ./update-ai-clis.sh skill-promote <skill_name|skill_dir>"
    exit 1
  fi

  bootstrap_config_files "verify"
  validate_base_locked

  if [[ -d "${skill_ref}" ]]; then
    local skill_dir
    skill_dir="$(resolve_abs_path "${skill_ref}")"
    local skill_name
    skill_name="$(basename "${skill_dir}")"
    if [[ "${skill_name}" == *"/"* || -z "${skill_name}" ]]; then
      error "Invalid skill directory name: ${skill_name}"
      exit 1
    fi
    copy_skill_dir_to_all_targets "${skill_dir}" "${skill_name}"
    return 0
  fi

  # If a name is passed, fallback to existing local-skill share behavior.
  share_skill_to_all_targets "${skill_ref}" "yes"
}

skill_share_all() {
  local maybe_arg="${1:-}"
  if [[ -n "${maybe_arg}" ]]; then
    error "Usage: ./update-ai-clis.sh skill-share-all"
    exit 1
  fi
  bootstrap_config_files "verify"
  validate_base_locked

  local -A local_skills=()
  local cli=""
  local target_dir=""
  local name=""

  for cli in claude gemini codex; do
    target_dir="$(skills_dir_for_cli "${cli}")" || exit 1
    while IFS= read -r name; do
      [[ -n "${name}" ]] || continue
      if [[ -f "${SKILLS_MASTER_DIR}/${name}/SKILL.md" ]]; then
        continue
      fi
      local_skills["${name}"]=1
    done < <(list_skill_names_in_dir "${target_dir}")
  done

  if [[ "${#local_skills[@]}" -eq 0 ]]; then
    info "No local-only skills found to share."
    return 0
  fi

  local shared=0
  local failed=0
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    if share_skill_to_all_targets "${name}" "yes"; then
      shared=$((shared + 1))
    else
      failed=$((failed + 1))
    fi
  done < <(printf "%s\n" "${!local_skills[@]}" | sort)

  if [[ "${failed}" -gt 0 ]]; then
    error "skill-share-all completed with errors: shared=${shared}, failed=${failed}"
    return 1
  fi

  info "Shared local skills across all CLIs: ${shared}"
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
    local project_dir=""
    if [[ -d "${project_ref}" ]]; then
      project_dir="$(resolve_abs_path "${project_ref}")"
      project_name="$(basename "${project_dir}")"
    elif [[ -f "${project_ref}" ]]; then
      local abs_ref=""
      abs_ref="$(resolve_abs_path "${project_ref}")"
      project_dir="$(dirname "${abs_ref}")"
      if [[ "$(basename "${abs_ref}")" == *.json ]]; then
        project_name="$(basename "${abs_ref}" .json)"
      else
        project_name="$(basename "${project_dir}")"
      fi
    else
      project_name="${project_ref}"
    fi

    local legacy_project_instructions=""
    if [[ -n "${project_name}" ]]; then
      legacy_project_instructions="${PROJECTS_DIR}/${project_name}.instructions.md"
    fi
    if [[ -n "${legacy_project_instructions}" && -f "${legacy_project_instructions}" ]]; then
      [[ -s "${merged}" ]] && printf "\n" >> "${merged}"
      cat "${legacy_project_instructions}" >> "${merged}"
    fi

    local project_local_instructions=""
    if [[ -n "${project_dir}" ]]; then
      project_local_instructions="${project_dir}/${PROJECT_LOCAL_INSTRUCTIONS_FILE_NAME}"
    fi
    if [[ -n "${project_local_instructions}" && -f "${project_local_instructions}" ]]; then
      [[ -s "${merged}" ]] && printf "\n" >> "${merged}"
      cat "${project_local_instructions}" >> "${merged}"
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
  if [[ ! -f "${BASE_LOCK_FILE}" ]]; then
    error "Base lock missing: ${BASE_LOCK_FILE}"
    error "Run './update-ai-clis.sh init' or './update-ai-clis.sh lock-base' from setupScript directory."
    exit 1
  fi
  local expected
  local actual
  expected="$(tr -d '[:space:]' < "${BASE_LOCK_FILE}")"
  actual="$(sha256_of_file "${BASE_REGISTRY_FILE}")"
  if [[ -z "${expected}" || "${expected}" != "${actual}" ]]; then
    error "base.json changed and is locked. Keep base as main baseline."
    error "Add extra features in <project>/.ai-stack.local.json or ai-config/local.json."
    error "Legacy overlay (ai-config/projects/<name>.json) is optional for compatibility."
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

assert_setupscript_dir() {
  local current_dir
  local script_dir
  current_dir="$(pwd -P)"
  script_dir="$(cd "${SCRIPT_DIR}" >/dev/null 2>&1 && pwd -P)"
  if [[ "${current_dir}" != "${script_dir}" ]]; then
    error "This command must be run from setupScript directory: ${SCRIPT_DIR}"
    error "Current directory: ${current_dir}"
    exit 1
  fi
}

is_project_context() {
  if [[ -n "${ACTIVE_PROJECT_REF}" ]]; then
    return 0
  fi

  local current_dir
  current_dir="$(pwd -P)"
  if [[ "${current_dir}" != "${SCRIPT_DIR}" && -f "${current_dir}/${PROJECT_LOCAL_FILE_NAME}" ]]; then
    return 0
  fi

  return 1
}

warn_promote_required() {
  warn "Project context detected. This command does not write user configs under ~/."
  warn "Use 'promote' or 'promote-here' to apply project settings to Claude/Codex/Gemini."
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
  local mode="${1:-verify}" # create|verify
  local allow_create="no"
  case "${mode}" in
    create) allow_create="yes" ;;
    verify) allow_create="no" ;;
    *)
      error "Invalid bootstrap mode: ${mode}"
      exit 1
      ;;
  esac

  if [[ "${allow_create}" == "yes" ]]; then
    mkdir -p "${CONFIG_DIR}" "${PROJECTS_DIR}" "${CONFIG_DIR}/backups"
  else
    if [[ ! -d "${CONFIG_DIR}" ]]; then
      error "Config directory missing: ${CONFIG_DIR}"
      error "Run './update-ai-clis.sh init' from setupScript directory first."
      exit 1
    fi
    mkdir -p "${CONFIG_DIR}/backups"
  fi

  if [[ ! -f "${BASE_REGISTRY_FILE}" ]]; then
    if [[ "${allow_create}" != "yes" ]]; then
      error "Baseline config missing: ${BASE_REGISTRY_FILE}"
      error "Run './update-ai-clis.sh init' from setupScript directory first."
      exit 1
    fi
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

  ensure_codex_base_file "${allow_create}"

  if [[ ! -f "${PROJECTS_DIR}/_example.json" ]]; then
    if [[ "${allow_create}" == "yes" ]]; then
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
  fi

  if [[ ! -f "${CONFIG_DIR}/README.md" ]]; then
    if [[ "${allow_create}" == "yes" ]]; then
      cat > "${CONFIG_DIR}/README.md" <<'EOF_README'
# ai-config

Layered configuration for Claude/Codex/Gemini baseline.
Main baseline (`base.json`) is intentionally locked.

## Files

- `base.json`: Global baseline (required, locked)
- `base.lock.sha256`: Lock hash for `base.json`
- `projects/<name>.json`: Legacy project overlay (optional, backward compatibility)
- `local.json`: Machine-local overlay (optional, do not commit)
- `skills/<name>/SKILL.md`: Managed skills master
- `agents/*.md`: Claude custom agents master
- `global-instructions.md`: Shared global instructions (optional)
- `global-instructions.local.md`: Machine-local instructions (optional, do not commit)
- `<project>/.ai-stack.local.json`: Project-local overlay (optional, can commit)
- `<project>/.ai-stack.instructions.md`: Project-local instructions (optional, can commit)

## Priority

`base.json` < `projects/<name>.json` < `local.json` < `<project>/.ai-stack.local.json`

## Recommended workflow

1. Keep `base.json` as stable minimal baseline.
2. Add project-specific features in `<project>/.ai-stack.local.json`.
3. Keep machine-specific secrets/path overrides in `local.json`.
4. Run `./update-ai-clis.sh sync-here` in each project folder.
5. Use `projects/<name>.json` only when you need legacy compatibility.

If you intentionally update `base.json`, run:

`./update-ai-clis.sh lock-base`
EOF_README
      info "Created docs: ${CONFIG_DIR}/README.md"
    fi
  fi

  ensure_skills_master "${allow_create}"
  ensure_agents_master "${allow_create}"

  if [[ "${allow_create}" == "yes" ]]; then
    ensure_base_lock
  fi
}

project_init() {
  ensure_node
  bootstrap_config_files "verify"
  validate_base_locked

  local raw_project_dir="${1:-$PWD}"
  if [[ ! -d "${raw_project_dir}" ]]; then
    error "Project directory not found: ${raw_project_dir}"
    exit 1
  fi

  local project_dir
  local folder_overlay
  local gitignore

  project_dir="$(resolve_abs_path "${raw_project_dir}")"
  assert_not_setupscript_dir "${project_dir}"
  folder_overlay="${project_dir}/${PROJECT_LOCAL_FILE_NAME}"
  gitignore="${project_dir}/.gitignore"

  if [[ -f "${folder_overlay}" ]]; then
    info "Project local config exists: ${folder_overlay}"
  else
    cat > "${folder_overlay}" <<'EOF_LOCAL'
{
  "projectServers": [],
  "servers": {}
}
EOF_LOCAL
    info "Created project local config: ${folder_overlay}"
  fi

  local backlog="${project_dir}/BACKLOG.md"
  if [[ -f "${backlog}" ]]; then
    info "BACKLOG.md already exists: ${backlog}"
  else
    cat > "${backlog}" <<'EOF_BACKLOG'
# Backlog

保留中のアイデアや、条件付きで将来実装する案を記録する。

## ルール

- 案ごとに「トリガー条件」を明記する（いつ再検討するか）
- 実装したら「完了」へ移動し、対応コミットを記載

## 保留中

（なし）

## 完了

（なし）
EOF_BACKLOG
    info "Created BACKLOG.md: ${backlog}"
  fi

  if [[ -f "${gitignore}" ]] && has_exact_line "${PROJECT_LOCAL_FILE_NAME}" "${gitignore}"; then
    warn "${gitignore} contains '${PROJECT_LOCAL_FILE_NAME}'."
    warn "Remove that line if you want to commit project config."
  fi

  ACTIVE_PROJECT_REF="${project_dir}"
  info "Project files initialized. User configs under ~/ are unchanged."
  preview_sync_diff
  warn "Run 'promote-here' in the project directory when you want to apply this project to user configs."
}

build_effective_registry() {
  ensure_node
  bootstrap_config_files "verify"
  validate_base_locked

  local project_ref="${1:-}"
  ACTIVE_PROJECT_REF="${project_ref}"

  local project_file=""
  local folder_local_file=""
  local folder_local_project_path=""
  local pwd_abs
  pwd_abs="$(pwd -P)"
  folder_local_file="${pwd_abs}/${PROJECT_LOCAL_FILE_NAME}"
  folder_local_project_path="${pwd_abs}"

  if [[ -n "${project_ref}" ]]; then
    if [[ -f "${project_ref}" ]]; then
      local abs_ref=""
      abs_ref="$(resolve_abs_path "${project_ref}")"
      if [[ "$(basename "${abs_ref}")" == "${PROJECT_LOCAL_FILE_NAME}" ]]; then
        folder_local_file="${abs_ref}"
        folder_local_project_path="$(dirname "${abs_ref}")"
        ACTIVE_PROJECT_REF="${folder_local_project_path}"
      else
        project_file="${abs_ref}"
        folder_local_project_path="$(dirname "${abs_ref}")"
        folder_local_file="${folder_local_project_path}/${PROJECT_LOCAL_FILE_NAME}"
      fi
    elif [[ -d "${project_ref}" ]]; then
      local project_dir_abs=""
      local name=""
      project_dir_abs="$(resolve_abs_path "${project_ref}")"
      folder_local_project_path="${project_dir_abs}"
      folder_local_file="${project_dir_abs}/${PROJECT_LOCAL_FILE_NAME}"
      ACTIVE_PROJECT_REF="${project_dir_abs}"
      name="$(basename "${project_dir_abs}")"
      if [[ -f "${PROJECTS_DIR}/${name}.json" ]]; then
        project_file="${PROJECTS_DIR}/${name}.json"
      fi
    elif [[ -f "${PROJECTS_DIR}/${project_ref}.json" ]]; then
      project_file="${PROJECTS_DIR}/${project_ref}.json"
    else
      warn "Project overlay not found for '${project_ref}'. Using Global/local config only."
    fi
  fi

  cleanup_effective_registry
  EFFECTIVE_REGISTRY="$(mktemp)"

EFFECTIVE_LAYERS="$(node - "${BASE_REGISTRY_FILE}" "${project_file}" "${GLOBAL_LOCAL_FILE}" "${folder_local_file}" "${EFFECTIVE_REGISTRY}" "${project_ref}" "${folder_local_project_path}" <<'NODE'
const fs = require("fs");

const basePath = process.argv[2];
const projectPath = process.argv[3];
const globalLocalPath = process.argv[4];
const folderLocalPath = process.argv[5];
const outPath = process.argv[6];
const projectRef = process.argv[7] || "";
const folderLocalProjectPath = process.argv[8] || "";

function existsFile(p) {
  return typeof p === "string" && p.length > 0 && fs.existsSync(p) && fs.statSync(p).isFile();
}

function isObject(v) {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function toStringArray(v) {
  if (!Array.isArray(v)) return [];
  return v
    .map((x) => String(x).trim())
    .filter((x) => x.length > 0);
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

  if ("projectServers" in merged && !Array.isArray(merged.projectServers)) {
    throw new Error("projectServers must be an array of server names.");
  }
  const projectServers = toStringArray(merged.projectServers);
  if (projectServers.length > 0 && folderLocalProjectPath.length > 0) {
    merged.projects[folderLocalProjectPath] = projectServers;
  }
  delete merged.projectServers;

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
      before_first_table=1;
      seen_root_web=0;
      inserted_root_web=0;
    }
    /^[[:space:]]*\[/ {
      if (before_first_table == 1 && inserted_root_web == 0) {
        print "web_search = \"live\"";
        print "";
        seen_root_web=1;
        inserted_root_web=1;
      }
      before_first_table=0;
    }
    /^[[:space:]]*\[tools\][[:space:]]*$/ {
      in_tools=1;
      print;
      next;
    }
    /^[[:space:]]*\[/ {
      in_tools=0;
    }
    {
      if (before_first_table == 1 && $0 ~ /^[[:space:]]*web_search[[:space:]]*=/) {
        if (seen_root_web == 0) {
          print "web_search = \"live\"";
          seen_root_web=1;
          inserted_root_web=1;
        }
        next;
      }
      if (in_tools == 1 && $0 ~ /^[[:space:]]*web_search[[:space:]]*=/) {
        next;
      }
      print;
    }
    END {
      if (seen_root_web == 0) {
        print "";
        print "web_search = \"live\"";
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
  info "Synced Codex defaults: web_search = \"live\""

  local claude_count
  claude_count="$(sync_claude_mcp)"
  info "Synced Claude MCP config: ${CLAUDE_JSON} (active servers: ${claude_count})"
  sync_claude_settings_defaults

  sync_gemini_settings_baseline
  sync_gemini_manifest
  sync_skills
  sync_agents
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
  sync_agents
  sync_global_instructions
  uninstall_npm_mcp_packages
  uninstall_pipx_mcp_packages
  info "Backup snapshot: ${BACKUP_DIR}"
}

wipe_user_settings() {
  local targets=(
    "${HOME}/.claude.json"
    "${HOME}/.claude/settings.json"
    "${HOME}/.claude/CLAUDE.md"
    "${HOME}/.claude/skills"
    "${HOME}/.claude/agents"
    "${HOME}/.codex/config.toml"
    "${HOME}/.codex/AGENTS.md"
    "${HOME}/.codex/skills"
    "${HOME}/.codex/agents"
    "${HOME}/.gemini/settings.json"
    "${HOME}/.gemini/mcp.managed.json"
    "${HOME}/.gemini/GEMINI.md"
    "${HOME}/.gemini/skills"
    "${HOME}/.gemini/agents"
  )

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: would remove user settings:"
    local t=""
    for t in "${targets[@]}"; do
      printf "  - %s\n" "${t}"
    done
    return 0
  fi

  local t=""
  for t in "${targets[@]}"; do
    if [[ -e "${t}" ]]; then
      rm -rf "${t}"
    fi
  done

  rmdir "${HOME}/.claude" 2>/dev/null || true
  rmdir "${HOME}/.codex" 2>/dev/null || true
  rmdir "${HOME}/.gemini" 2>/dev/null || true

  info "Wiped user settings under ~/.claude ~/.codex ~/.gemini"
}

reset_user_from_git() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    preview_sync_diff
    return 0
  fi
  ACTIVE_PROJECT_REF=""
  sync_all
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

  local codex_web="unset"
  if [[ -f "${CODEX_TOML}" ]]; then
    if grep -qE '^[[:space:]]*web_search[[:space:]]*=[[:space:]]*"live"' "${CODEX_TOML}"; then
      codex_web="live"
    elif grep -qE '^[[:space:]]*web_search[[:space:]]*=[[:space:]]*"cached"' "${CODEX_TOML}"; then
      codex_web="cached"
    elif grep -qE '^[[:space:]]*web_search[[:space:]]*=[[:space:]]*"disabled"' "${CODEX_TOML}"; then
      codex_web="disabled"
    elif grep -qE '^[[:space:]]*web_search[[:space:]]*=[[:space:]]*true' "${CODEX_TOML}"; then
      codex_web="live (legacy)"
    elif grep -qE '^[[:space:]]*web_search[[:space:]]*=[[:space:]]*false' "${CODEX_TOML}"; then
      codex_web="disabled (legacy)"
    fi
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

  local master_agent_count
  local claude_agent_count
  local gemini_agent_count
  local codex_agent_count
  local master_agent_hash
  local claude_agent_hash
  local gemini_agent_hash
  local codex_agent_hash
  master_agent_count="$(count_agent_files_in_dir "${AGENTS_MASTER_DIR}")"
  claude_agent_count="$(count_agent_files_in_dir "${CLAUDE_AGENTS_DIR}")"
  gemini_agent_count="$(count_agent_files_in_dir "${GEMINI_AGENTS_DIR}")"
  codex_agent_count="$(count_agent_files_in_dir "${CODEX_AGENTS_DIR}")"
  master_agent_hash="$(agent_tree_hash "${AGENTS_MASTER_DIR}" | cut -c1-12)"
  claude_agent_hash="$(agent_tree_hash "${CLAUDE_AGENTS_DIR}" | cut -c1-12)"
  gemini_agent_hash="$(agent_tree_hash "${GEMINI_AGENTS_DIR}" | cut -c1-12)"
  codex_agent_hash="$(agent_tree_hash "${CODEX_AGENTS_DIR}" | cut -c1-12)"
  printf "  %-24s %s (hash:%s)\n" "Agents master:" "${master_agent_count}" "${master_agent_hash}"
  printf "  %-24s %s (hash:%s)\n" "Claude agents:" "${claude_agent_count}" "${claude_agent_hash}"
  printf "  %-24s %s (hash:%s)\n" "Gemini agents:" "${gemini_agent_count}" "${gemini_agent_hash}"
  printf "  %-24s %s (hash:%s)\n" "Codex agents:" "${codex_agent_count}" "${codex_agent_hash}"

  if [[ -f "${GLOBAL_INSTRUCTIONS}" ]]; then
    local instr_hash
    instr_hash="$(sha256_short "${GLOBAL_INSTRUCTIONS}")"
    local layers_info="${instr_hash}"
    if [[ -n "${ACTIVE_PROJECT_REF}" ]]; then
      local _pn=""
      local _pd=""
      if [[ -d "${ACTIVE_PROJECT_REF}" ]]; then
        _pd="$(resolve_abs_path "${ACTIVE_PROJECT_REF}")"
        _pn="$(basename "${_pd}")"
      elif [[ -f "${ACTIVE_PROJECT_REF}" ]]; then
        _pd="$(dirname "$(resolve_abs_path "${ACTIVE_PROJECT_REF}")")"
        if [[ "$(basename "${ACTIVE_PROJECT_REF}")" == *.json ]]; then
          _pn="$(basename "${ACTIVE_PROJECT_REF}" .json)"
        else
          _pn="$(basename "${_pd}")"
        fi
      else
        _pn="${ACTIVE_PROJECT_REF}"
      fi
      if [[ -n "${_pn}" && -f "${PROJECTS_DIR}/${_pn}.instructions.md" ]]; then
        layers_info="${layers_info}+project-legacy"
      fi
      if [[ -n "${_pd}" && -f "${_pd}/${PROJECT_LOCAL_INSTRUCTIONS_FILE_NAME}" ]]; then
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

  print_sync_drift_status
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

  check_agents_match() {
    local label="$1" master_dir="$2" target_dir="$3"
    local master_count
    master_count="$(count_agent_files_in_dir "${master_dir}")"
    if [[ "${master_count}" -eq 0 ]]; then
      return 0
    fi
    if [[ ! -d "${target_dir}" ]]; then
      warn "Drift: ${label} agents directory missing"
      drift=1
      return 0
    fi

    local tmp_rendered
    tmp_rendered="$(mktemp -d)"
    local src rel exp_agent act_agent
    while IFS= read -r src; do
      [[ -n "${src}" ]] || continue
      rel="${src#${master_dir}/}"
      exp_agent="${tmp_rendered}/${rel}"
      mkdir -p "$(dirname "${exp_agent}")"
      cp -a "${src}" "${exp_agent}"
    done < <(find "${master_dir}" -mindepth 1 -type f \
      ! -name 'README.md' \
      ! -path '*/.*' \
      -print 2>/dev/null | sort)

    while IFS= read -r src; do
      [[ -n "${src}" ]] || continue
      rel="${src#${master_dir}/}"
      exp_agent="${tmp_rendered}/${rel}"
      act_agent="${target_dir}/${rel}"
      if [[ ! -f "${act_agent}" ]]; then
        warn "Drift: ${label} agent '${rel}' missing"
        drift=1
      elif ! cmp -s "${exp_agent}" "${act_agent}"; then
        warn "Drift: ${label} agent '${rel}' content mismatch"
        drift=1
      fi
    done < <(find "${master_dir}" -mindepth 1 -type f \
      ! -name 'README.md' \
      ! -path '*/.*' \
      -print 2>/dev/null | sort)

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
  check_agents_match "Claude" "${AGENTS_MASTER_DIR}" "${CLAUDE_AGENTS_DIR}"
  check_agents_match "Gemini" "${AGENTS_MASTER_DIR}" "${GEMINI_AGENTS_DIR}"
  check_agents_match "Codex" "${AGENTS_MASTER_DIR}" "${CODEX_AGENTS_DIR}"

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

file_pair_different() {
  local left="$1"
  local right="$2"

  if [[ ! -e "${left}" && ! -e "${right}" ]]; then
    return 1
  fi
  if [[ ! -e "${left}" || ! -e "${right}" ]]; then
    return 0
  fi
  if cmp -s "${left}" "${right}"; then
    return 1
  fi
  return 0
}

build_sync_preview_snapshot() {
  local preview_root="$1"

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

  sync_all >/dev/null
}

print_sync_drift_status() {
  local preview_root
  preview_root="$(mktemp -d)"
  build_sync_preview_snapshot "${preview_root}"

  local claude_state="in-sync"
  local codex_state="in-sync"
  local gemini_state="in-sync"

  if file_pair_different "${CLAUDE_JSON}" "${preview_root}/.claude.json" || \
     file_pair_different "${CLAUDE_SETTINGS}" "${preview_root}/.claude/settings.json"; then
    claude_state="diff"
  fi
  if file_pair_different "${CODEX_TOML}" "${preview_root}/.codex/config.toml"; then
    codex_state="diff"
  fi
  if file_pair_different "${GEMINI_SETTINGS}" "${preview_root}/.gemini/settings.json" || \
     file_pair_different "${GEMINI_MCP_MANAGED}" "${preview_root}/.gemini/mcp.managed.json"; then
    gemini_state="diff"
  fi

  local master_agent_hash
  local claude_agent_hash
  local gemini_agent_hash
  local codex_agent_hash
  master_agent_hash="$(agent_tree_hash "${AGENTS_MASTER_DIR}")"
  claude_agent_hash="$(agent_tree_hash "${CLAUDE_AGENTS_DIR}")"
  gemini_agent_hash="$(agent_tree_hash "${GEMINI_AGENTS_DIR}")"
  codex_agent_hash="$(agent_tree_hash "${CODEX_AGENTS_DIR}")"
  if [[ "${master_agent_hash}" != "empty" && "${master_agent_hash}" != "n/a" ]]; then
    if [[ "${master_agent_hash}" != "${claude_agent_hash}" ]]; then
      claude_state="diff"
    fi
    if [[ "${master_agent_hash}" != "${gemini_agent_hash}" ]]; then
      gemini_state="diff"
    fi
    if [[ "${master_agent_hash}" != "${codex_agent_hash}" ]]; then
      codex_state="diff"
    fi
  fi

  printf "  %-24s %s\n" "Drift Claude:" "${claude_state}"
  printf "  %-24s %s\n" "Drift Codex:" "${codex_state}"
  printf "  %-24s %s\n" "Drift Gemini:" "${gemini_state}"

  rm -rf "${preview_root}"
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
      assert_setupscript_dir
      bootstrap_config_files "create"
      reset_user_from_git
      ;;
    lock-base)
      assert_setupscript_dir
      bootstrap_config_files "verify"
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
      elif is_project_context; then
        warn_promote_required
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
        warn_promote_required
        preview_sync_diff
      fi
      ;;
    promote)
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        preview_sync_diff
      else
        sync_all
      fi
      ;;
    promote-here)
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
      # Preflight first to avoid partial state where CLI update succeeds but sync later fails.
      build_effective_registry "${ACTIVE_PROJECT_REF}"
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        update_clis
        divider
        preview_sync_diff
      else
        update_clis
        divider
        if is_project_context; then
          warn_promote_required
          preview_sync_diff
        else
          sync_all
        fi
      fi
      ;;
    all-here)
      assert_not_setupscript_dir "${PWD}"
      ACTIVE_PROJECT_REF="${PWD}"
      # Preflight first to avoid partial state where CLI update succeeds but sync later fails.
      build_effective_registry "${ACTIVE_PROJECT_REF}"
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        update_clis
        divider
        preview_sync_diff
      else
        update_clis
        divider
        warn_promote_required
        preview_sync_diff
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
    skill-share)
      skill_share "${project_ref}"
      ;;
    skill-promote)
      skill_promote "${project_ref}"
      ;;
    skill-share-all)
      skill_share_all "${project_ref}"
      ;;
    wipe-user)
      wipe_user_settings
      ;;
    reset-user)
      assert_setupscript_dir
      bootstrap_config_files "verify"
      validate_base_locked
      reset_user_from_git
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
