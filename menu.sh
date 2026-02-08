#!/usr/bin/env bash
# menu.sh - Interactive wrapper for update-ai-clis.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/update-ai-clis.sh"
START_PWD="$(pwd -P)"
LAST_PROJECT_DIR=""
INTRO_SHOWN=0

if [[ ! -x "${MAIN_SCRIPT}" ]]; then
  echo "[ERROR] update-ai-clis.sh が見つからないか実行権限がありません: ${MAIN_SCRIPT}" >&2
  exit 1
fi

ui_message() {
  local title="$1"
  local message="$2"
  echo >&2
  echo "== ${title} ==" >&2
  printf '%b\n' "${message}" >&2
}

pause_prompt() {
  read -r -p $'\nEnterで続行します...' _
}

ui_confirm() {
  local message="$1"
  local default="${2:-N}"
  local answer=""
  local prompt=""

  if [[ "${default}" == "Y" ]]; then
    prompt="$(printf '%b' "${message}") [Y/n]: "
    read -r -p "${prompt}" answer
    answer="${answer:-Y}"
  else
    prompt="$(printf '%b' "${message}") [y/N]: "
    read -r -p "${prompt}" answer
    answer="${answer:-N}"
  fi
  case "${answer}" in
    y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

ui_input() {
  local title="$1"
  local message="$2"
  local default="${3:-}"
  local value=""

  if [[ -n "${default}" ]]; then
    read -r -p "${message} (空なら ${default}): " value || return 1
    value="${value:-${default}}"
  else
    read -r -p "${message}: " value || return 1
  fi

  printf "%s\n" "${value}"
}

to_abs_if_exists() {
  local input="$1"
  if [[ "${input}" == "~"* ]]; then
    input="${HOME}${input:1}"
  fi
  if [[ -e "${input}" ]]; then
    if command -v realpath >/dev/null 2>&1; then
      realpath "${input}"
    else
      (
        cd "$(dirname "${input}")" >/dev/null 2>&1
        printf "%s/%s\n" "$(pwd -P)" "$(basename "${input}")"
      )
    fi
  else
    printf "%s\n" "${input}"
  fi
}

ask_project_ref_optional() {
  local ref=""
  if ! ref="$(ui_input "プロジェクト指定" "プロジェクト名/パス（空で省略）" "")"; then
    return 1
  fi
  if [[ -z "${ref}" ]]; then
    printf "\n"
    return 0
  fi
  to_abs_if_exists "${ref}"
}

ask_directory_required() {
  local title="$1"
  local default_dir="$2"
  local input=""

  while true; do
    if ! input="$(ui_input "${title}" "対象ディレクトリを入力" "${default_dir}")"; then
      return 1
    fi
    if [[ "${input}" == "~"* ]]; then
      input="${HOME}${input:1}"
    fi
    if [[ -d "${input}" ]]; then
      if command -v realpath >/dev/null 2>&1; then
        realpath "${input}"
      else
        (
          cd "${input}" >/dev/null 2>&1
          pwd -P
        )
      fi
      return 0
    fi
    ui_message "入力エラー" "ディレクトリが存在しません:\n${input}\n\n再入力してください。"
  done
}

default_project_dir_for_prompt() {
  if [[ -n "${LAST_PROJECT_DIR}" && -d "${LAST_PROJECT_DIR}" ]]; then
    printf "%s\n" "${LAST_PROJECT_DIR}"
    return 0
  fi
  if [[ "${START_PWD}" != "${SCRIPT_DIR}" ]]; then
    printf "%s\n" "${START_PWD}"
    return 0
  fi
  printf "\n"
}

ask_skill_name_required() {
  local value=""
  while true; do
    if ! value="$(ui_input "スキル名" "共有するスキル名を入力（例: pj-my-skill）" "")"; then
      return 1
    fi
    if [[ -z "${value}" ]]; then
      ui_message "入力エラー" "スキル名は必須です。"
      continue
    fi
    if [[ "${value}" == *"/"* ]]; then
      ui_message "入力エラー" "スキル名には '/' を含めないでください。"
      continue
    fi
    printf "%s\n" "${value}"
    return 0
  done
}

show_intro_once() {
  if [[ "${INTRO_SHOWN}" -eq 1 ]]; then
    return 0
  fi
  INTRO_SHOWN=1

  cat <<'EOF_INTRO'

========================================
 AI CLI 設定メニュー
========================================
このメニューは Claude / Codex / Gemini の共通設定管理を、
説明付きで実行するラッパーです。

使い方の目安:
  1. 初回: project-init
  2. 日常: sync-here -> status-here
  3. 復旧: reset-here（必要なら --dry-run）
  4. 詳細操作: 日常メニューで a を選択
========================================
EOF_INTRO
}

show_help_text() {
  local help_file=""
  help_file="$(mktemp)"
  cat >"${help_file}" <<'EOF_HELP'
[クイックガイド]
- まず使う:
  project-init -> sync-here -> status-here
- 変更前確認:
  diff または sync-here/reset-here + --dry-run
- 迷ったら:
  メインメニューの「ガイド」を参照

[コマンドの使い分け]
- メインメニュー:
  日常運用で使う最小コマンドのみ表示
- 詳細メニュー:
  すべてのコマンド（上級者向け）
- init:
  setupScript 配下の必須ファイルを初期化（初回のみ）
- lock-base:
  base.json を意図的に変更したときだけロック更新
- update:
  CLI本体更新（設定配布はしない）
- sync:
  レイヤーをマージして3CLIへ配布
- reset:
  設定をベースへ戻し、skills / instructions を再配布
- all:
  update + sync を連続実行
- diff:
  syncした場合の差分を確認
- check:
  skills / instructions のドリフト検知（CI向け）
- status:
  現在状態（レイヤー、MCP数、skills 等）を表示
- project-init:
  プロジェクト雛形を作成して初回syncまで実施
- *-here:
  指定したプロジェクトディレクトリ基準で実行
- skill-share:
  ローカルスキル1件を3CLIへ共有（managed skillは除く）
- skill-share-all:
  ローカルスキルを3CLIへ一括共有（managed skillは除く）

[安全運用のポイント]
- reset / all の前は --dry-run を推奨
- setupScript 直下専用:
  init / lock-base
- PJフォルダ推奨:
  project-init / sync-here / status-here
- setupScript 直下で *-here を使う場合:
  先に対象PJディレクトリを入力する
EOF_HELP

  echo
  cat "${help_file}"
  rm -f "${help_file}"
}

strip_ansi() {
  sed $'s/\x1b\\[[0-9;]*m//g'
}

run_update_ai() {
  local workdir="$1"
  shift
  local quoted=""
  local rc=0
  quoted="$(printf "%q " "$@")"

  local log_file=""
  log_file="$(mktemp)"

  # ログヘッダー書き込み
  echo "[RUN] (cd ${workdir} && ./update-ai-clis.sh ${quoted})" >"${log_file}"
  echo "" >>"${log_file}"

  # コマンドをバックグラウンド実行（stdin遮断で read 競合を防止）
  (
    cd "${workdir}" >/dev/null 2>&1
    "${MAIN_SCRIPT}" "$@"
  ) >>"${log_file}" 2>&1 </dev/null &
  local pid=$!

  # --- ASCII プログレスバー ---
  echo
  echo ">> 実行中: ${quoted}"

  local pct=0
  local status_line=""
  local bar=""
  local bar_width=30
  local filled=0
  local empty=0

  while kill -0 "${pid}" 2>/dev/null; do
    status_line="$(tail -n 1 "${log_file}" 2>/dev/null | strip_ansi | cut -c 1-20)"
    if [[ "${pct}" -lt 90 ]]; then
      pct=$((pct + 1))
    fi
    filled=$((pct * bar_width / 100))
    empty=$((bar_width - filled))
    bar=""
    for ((i = 0; i < filled; i++)); do bar+="#"; done
    for ((i = 0; i < empty; i++)); do bar+="-"; done
    printf "\r[%s] %3d%% %-24s" "${bar}" "${pct}" "${status_line:-実行中...}"
    sleep 0.3
  done

  # 完了表示
  bar=""
  for ((i = 0; i < bar_width; i++)); do bar+="#"; done
  printf "\r[%s] 100%% %-24s\n" "${bar}" "完了"

  wait "${pid}" 2>/dev/null
  rc=$?

  echo ""
  cat "${log_file}"

  if [[ "${rc}" -eq 0 ]]; then
    echo "[OK] 正常終了"
  else
    echo "[ERROR] 終了コード: ${rc}"
  fi

  rm -f "${log_file}"
  return "${rc}"
}

ask_dry_run() {
  ui_confirm "--dry-run で実行しますか？\n(設定変更は行わず、予定のみ表示します)" "N"
}

run_project_cmd() {
  local cmd="$1"
  local allow_dry="$2"
  local args=("${cmd}")
  local ref=""

  if ! ref="$(ask_project_ref_optional)"; then
    ui_message "キャンセル" "入力をキャンセルしました。"
    return 0
  fi
  if [[ -n "${ref}" ]]; then
    args+=("${ref}")
  fi
  if [[ "${allow_dry}" == "yes" ]] && ask_dry_run; then
    args+=("--dry-run")
  fi

  if [[ "${cmd}" == "reset" || "${cmd}" == "all" ]]; then
    if ! ui_confirm "${cmd} は設定の再配布やアンインストール処理を含みます。\n実行しますか？" "N"; then
      ui_message "キャンセル" "処理を中止しました。"
      return 0
    fi
  fi

  run_update_ai "${SCRIPT_DIR}" "${args[@]}"
}

run_here_cmd() {
  local cmd="$1"
  local allow_dry="$2"
  local target_dir=""
  local args=("${cmd}")
  local default_dir=""

  default_dir="$(default_project_dir_for_prompt)"
  if ! target_dir="$(ask_directory_required "${cmd}" "${default_dir}")"; then
    ui_message "キャンセル" "入力をキャンセルしました。"
    return 0
  fi
  if [[ "${target_dir}" == "${SCRIPT_DIR}" ]]; then
    ui_message "入力エラー" "setupScript フォルダ自体は指定できません。\nプロジェクトフォルダを指定してください。"
    return 0
  fi

  LAST_PROJECT_DIR="${target_dir}"

  if [[ "${allow_dry}" == "yes" ]] && ask_dry_run; then
    args+=("--dry-run")
  fi

  if [[ "${cmd}" == "reset-here" || "${cmd}" == "all-here" ]]; then
    if ! ui_confirm "${cmd} は設定の再配布やアンインストール処理を含みます。\n実行しますか？" "N"; then
      ui_message "キャンセル" "処理を中止しました。"
      return 0
    fi
  fi

  run_update_ai "${target_dir}" "${args[@]}"
}

run_project_init() {
  local target_dir=""
  local default_dir=""
  default_dir="$(default_project_dir_for_prompt)"
  if ! target_dir="$(ask_directory_required "project-init" "${default_dir}")"; then
    ui_message "キャンセル" "入力をキャンセルしました。"
    return 0
  fi
  if [[ "${target_dir}" == "${SCRIPT_DIR}" ]]; then
    ui_message "入力エラー" "setupScript フォルダ自体は指定できません。\nプロジェクトフォルダを指定してください。"
    return 0
  fi
  LAST_PROJECT_DIR="${target_dir}"
  run_update_ai "${SCRIPT_DIR}" project-init "${target_dir}"
}

run_skill_share() {
  local skill_name=""
  local args=()
  if ! skill_name="$(ask_skill_name_required)"; then
    ui_message "キャンセル" "入力をキャンセルしました。"
    return 0
  fi
  args=(skill-share "${skill_name}")
  if ask_dry_run; then
    args+=("--dry-run")
  fi
  run_update_ai "${SCRIPT_DIR}" "${args[@]}"
}

run_skill_share_all() {
  local args=(skill-share-all)
  if ask_dry_run; then
    args+=("--dry-run")
  fi
  if ! ui_confirm "3CLI間でローカルスキルを一括共有します。\n実行しますか？" "N"; then
    ui_message "キャンセル" "処理を中止しました。"
    return 0
  fi
  run_update_ai "${SCRIPT_DIR}" "${args[@]}"
}

print_main_menu_text() {
  cat <<'EOF_MENU'

========================================
 AI CLI 設定メニュー（日常）
========================================
 1) project-init   : PJ初期化（初回）
 2) sync-here      : 設定同期（推奨）
 3) status-here    : 状態確認（推奨）
 4) diff [project] : 変更予定確認
 5) reset-here     : 復旧（注意）
 6) skill-share    : ローカルスキル1件共有
 7) skill-share-all: ローカルスキル一括共有
 8) ガイド         : 使い分けを表示

 a) 詳細メニュー   : 全コマンドを表示
 q) 終了
========================================
EOF_MENU
}

print_advanced_menu_text() {
  cat <<'EOF_MENU'

========================================
 AI CLI 設定メニュー（詳細）
========================================
 [初期化/保守]
 1) init
 2) lock-base
 3) update

 [通常運用]
 4) sync [project]
 5) reset [project]
 6) all [project]
 7) diff [project]
 8) check [project]
 9) status [project]

 [PJ運用]
10) project-init
11) sync-here
12) reset-here
13) all-here
14) status-here

 [補助]
15) help
16) skill-share
17) skill-share-all
 b) 戻る
 q) 終了
========================================
EOF_MENU
}

select_main_menu() {
  local choice=""
  print_main_menu_text >&2
  read -r -p "番号を選択してください: " choice || return 1
  printf "%s\n" "${choice}"
}

select_advanced_menu() {
  local choice=""
  print_advanced_menu_text >&2
  read -r -p "番号を選択してください: " choice || return 1
  printf "%s\n" "${choice}"
}

handle_advanced_menu() {
  while true; do
    local adv=""
    if ! adv="$(select_advanced_menu)"; then
      return 0
    fi

    case "${adv}" in
      1) run_update_ai "${SCRIPT_DIR}" init ;;
      2) run_update_ai "${SCRIPT_DIR}" lock-base ;;
      3) run_update_ai "${SCRIPT_DIR}" update ;;
      4) run_project_cmd "sync" "yes" ;;
      5) run_project_cmd "reset" "yes" ;;
      6) run_project_cmd "all" "yes" ;;
      7) run_project_cmd "diff" "no" ;;
      8) run_project_cmd "check" "no" ;;
      9) run_project_cmd "status" "no" ;;
      10) run_project_init ;;
      11) run_here_cmd "sync-here" "yes" ;;
      12) run_here_cmd "reset-here" "yes" ;;
      13) run_here_cmd "all-here" "yes" ;;
      14) run_here_cmd "status-here" "no" ;;
      15) run_update_ai "${SCRIPT_DIR}" --help ;;
      16) run_skill_share ;;
      17) run_skill_share_all ;;
      b|B|back) return 0 ;;
      q|Q|quit|exit) return 1 ;;
      *)
        ui_message "入力エラー" "無効な選択です。"
        ;;
    esac

    pause_prompt
  done
}

main() {
  show_intro_once

  while true; do
    local choice=""
    if ! choice="$(select_main_menu)"; then
      ui_message "終了" "入力を受け取れなかったため終了します。"
      break
    fi

    case "${choice}" in
      1) run_project_init ;;
      2) run_here_cmd "sync-here" "yes" ;;
      3) run_here_cmd "status-here" "no" ;;
      4) run_project_cmd "diff" "no" ;;
      5) run_here_cmd "reset-here" "yes" ;;
      6) run_skill_share ;;
      7) run_skill_share_all ;;
      8) show_help_text ;;
      a|A)
        if ! handle_advanced_menu; then
          break
        fi
        ;;
      q|Q|quit|exit) break ;;
      *)
        ui_message "入力エラー" "無効な選択です。"
        ;;
    esac

    pause_prompt
  done

  echo "終了します。"
}

main "$@"
