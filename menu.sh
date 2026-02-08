#!/usr/bin/env bash
# menu.sh - Interactive wrapper for update-ai-clis.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/update-ai-clis.sh"
START_PWD="$(pwd -P)"

USE_WHIPTAIL=0
if command -v whiptail >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
  USE_WHIPTAIL=1
fi

WT_HEIGHT=24
WT_WIDTH=100
WT_MENU_HEIGHT=16
INTRO_SHOWN=0

if [[ ! -x "${MAIN_SCRIPT}" ]]; then
  echo "[ERROR] update-ai-clis.sh が見つからないか実行権限がありません: ${MAIN_SCRIPT}" >&2
  exit 1
fi

ui_message() {
  local title="$1"
  local message="$2"
  if [[ "${USE_WHIPTAIL}" -eq 1 ]]; then
    whiptail --title "${title}" --msgbox "${message}" 14 "${WT_WIDTH}"
  else
    echo
    echo "== ${title} =="
    echo "${message}"
  fi
}

pause_if_text_mode() {
  if [[ "${USE_WHIPTAIL}" -eq 0 ]]; then
    read -r -p $'\nEnterで続行します...' _
  fi
}

ui_confirm() {
  local message="$1"
  local default="${2:-N}"
  local answer=""

  if [[ "${USE_WHIPTAIL}" -eq 1 ]]; then
    local opt=()
    if [[ "${default}" != "Y" ]]; then
      opt+=(--defaultno)
    fi
    whiptail --title "確認" "${opt[@]}" --yesno "${message}" 14 "${WT_WIDTH}"
    return $?
  fi

  if [[ "${default}" == "Y" ]]; then
    read -r -p "${message} [Y/n]: " answer
    answer="${answer:-Y}"
  else
    read -r -p "${message} [y/N]: " answer
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

  if [[ "${USE_WHIPTAIL}" -eq 1 ]]; then
    if ! value="$(whiptail --title "${title}" --inputbox "${message}" 14 "${WT_WIDTH}" "${default}" 3>&1 1>&2 2>&3)"; then
      return 1
    fi
  else
    if [[ -n "${default}" ]]; then
      read -r -p "${message} (空なら ${default}): " value || return 1
      value="${value:-${default}}"
    else
      read -r -p "${message}: " value || return 1
    fi
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

show_intro_once() {
  if [[ "${INTRO_SHOWN}" -eq 1 ]]; then
    return 0
  fi
  INTRO_SHOWN=1

  if [[ "${USE_WHIPTAIL}" -eq 1 ]]; then
    ui_message "AI CLI 設定メニュー" \
"このメニューは Claude / Codex / Gemini の共通設定管理を、説明付きで実行するラッパーです。

使い方の目安:
1. 初回: init -> sync -> status -> check
2. 日常: sync / status / check
3. 復旧: reset（必要なら --dry-run で先に確認）

UIモード: whiptail（Ubuntu標準のダイアログUI）"
  else
    cat <<'EOF_INTRO'

========================================
 AI CLI 設定メニュー
========================================
このメニューは Claude / Codex / Gemini の共通設定管理を、
説明付きで実行するラッパーです。

使い方の目安:
  1. 初回: init -> sync -> status -> check
  2. 日常: sync / status / check
  3. 復旧: reset（必要なら --dry-run）

UIモード: テキスト（whiptail 未導入のため）
========================================
EOF_INTRO
  fi
}

show_help_text() {
  local help_file=""
  help_file="$(mktemp)"
  cat >"${help_file}" <<'EOF_HELP'
[クイックガイド]
- 初回セットアップ:
  init -> sync -> status -> check
- プロジェクト運用:
  project-init -> status-here -> sync-here
- 変更前確認:
  diff または sync/reset/all + --dry-run

[コマンドの使い分け]
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

[安全運用のポイント]
- reset / all の前は --dry-run を推奨
- setupScript 直下専用:
  init / lock-base
- PJフォルダ推奨:
  project-init / sync-here / status-here
EOF_HELP

  if [[ "${USE_WHIPTAIL}" -eq 1 ]]; then
    whiptail --title "メニューガイド" --scrolltext --textbox "${help_file}" 28 104
  else
    echo
    cat "${help_file}"
  fi
  rm -f "${help_file}"
}

run_update_ai() {
  local workdir="$1"
  shift
  local quoted=""
  local rc=0
  quoted="$(printf "%q " "$@")"

  if [[ "${USE_WHIPTAIL}" -eq 1 ]]; then
    local log_file=""
    local title=""
    log_file="$(mktemp)"
    {
      echo "[RUN] (cd ${workdir} && ./update-ai-clis.sh ${quoted})"
      echo
      (
        cd "${workdir}" >/dev/null 2>&1
        "${MAIN_SCRIPT}" "$@"
      )
    } >"${log_file}" 2>&1
    rc=$?

    if [[ "${rc}" -eq 0 ]]; then
      echo "" >>"${log_file}"
      echo "[OK] 正常終了" >>"${log_file}"
      title="実行結果: 成功"
    else
      echo "" >>"${log_file}"
      echo "[ERROR] 終了コード: ${rc}" >>"${log_file}"
      title="実行結果: 失敗"
    fi

    whiptail --title "${title}" --scrolltext --textbox "${log_file}" 28 104
    rm -f "${log_file}"
    return "${rc}"
  fi

  echo
  echo "[RUN] (cd ${workdir} && ./update-ai-clis.sh ${quoted})"
  (
    cd "${workdir}" >/dev/null 2>&1
    "${MAIN_SCRIPT}" "$@"
  )
  rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    echo "[OK] 正常終了"
  else
    echo "[ERROR] 終了コード: ${rc}"
  fi
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

  if ! target_dir="$(ask_directory_required "${cmd}")"; then
    ui_message "キャンセル" "入力をキャンセルしました。"
    return 0
  fi
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
  if ! target_dir="$(ask_directory_required "project-init")"; then
    ui_message "キャンセル" "入力をキャンセルしました。"
    return 0
  fi
  run_update_ai "${SCRIPT_DIR}" project-init "${target_dir}"
}

print_menu_text() {
  cat <<'EOF_MENU'

========================================
 AI CLI 設定メニュー
========================================
 [初期化/保守]
 1) init           : 初回セットアップ
 2) lock-base      : base.json ロック更新
 3) update         : CLI本体更新のみ

 [日常運用]
 4) sync [project] : 設定を3CLIへ配布
 5) reset [project]: ベースへ戻す（注意）
 6) all [project]  : update + sync
 7) diff [project] : 変更予定確認
 8) check [project]: ドリフト検知
 9) status [project]: 現在状態確認

 [プロジェクト運用]
10) project-init   : PJ初期化+sync
11) sync-here      : 指定PJで同期
12) reset-here     : 指定PJでリセット
13) all-here       : 指定PJで update+sync
14) status-here    : 指定PJの状態確認

 [情報]
15) help           : update-ai-clis.sh --help
16) ガイド         : 用途と推奨フローを表示
 q) 終了
========================================
EOF_MENU
}

select_menu() {
  local choice=""

  if [[ "${USE_WHIPTAIL}" -eq 1 ]]; then
    if ! choice="$(whiptail \
      --title "AI CLI 設定メニュー" \
      --menu "目的に合わせてコマンドを選択してください。" \
      "${WT_HEIGHT}" "${WT_WIDTH}" "${WT_MENU_HEIGHT}" \
      "1"  "init: 初回セットアップ（setupScript配下のみ）" \
      "2"  "lock-base: base.json変更時のみロック更新" \
      "3"  "update: CLI本体更新のみ" \
      "4"  "sync [project]: 3CLIへ設定配布" \
      "5"  "reset [project]: ベースへ戻す（注意）" \
      "6"  "all [project]: update + sync" \
      "7"  "diff [project]: 変更予定の確認" \
      "8"  "check [project]: ドリフト検知（CI向け）" \
      "9"  "status [project]: 現在状態の確認" \
      "10" "project-init [dir]: PJ雛形作成+初回sync" \
      "11" "sync-here: 指定PJディレクトリで同期" \
      "12" "reset-here: 指定PJディレクトリでリセット" \
      "13" "all-here: 指定PJディレクトリで update+sync" \
      "14" "status-here: 指定PJディレクトリ状態表示" \
      "15" "help: update-ai-clis.sh のヘルプ表示" \
      "16" "メニューガイド: 推奨フローと注意点" \
      "q"  "終了" \
      3>&1 1>&2 2>&3)"; then
      return 1
    fi
    printf "%s\n" "${choice}"
    return 0
  fi

  print_menu_text >&2
  read -r -p "番号を選択してください: " choice || return 1
  printf "%s\n" "${choice}"
}

main() {
  show_intro_once

  while true; do
    local choice=""
    if ! choice="$(select_menu)"; then
      if [[ "${USE_WHIPTAIL}" -eq 1 ]]; then
        break
      fi
      ui_message "終了" "入力を受け取れなかったため終了します。"
      break
    fi

    case "${choice}" in
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
      16) show_help_text ;;
      q|Q|quit|exit) break ;;
      *)
        ui_message "入力エラー" "無効な選択です。"
        ;;
    esac

    pause_if_text_mode
  done

  if [[ "${USE_WHIPTAIL}" -eq 0 ]]; then
    echo "終了します。"
  fi
}

main "$@"
