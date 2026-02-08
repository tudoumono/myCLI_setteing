#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
TMP_HOME="$(mktemp -d)"
TMP_PROJECT="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_ROOT}" "${TMP_HOME}" "${TMP_PROJECT}" "${MOCK_BIN}"
}
trap cleanup EXIT

cat > "${MOCK_BIN}/npm" <<'EOF_NPM'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_NPM
chmod +x "${MOCK_BIN}/npm"

cat > "${MOCK_BIN}/pipx" <<'EOF_PIPX'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list" ]]; then
  exit 0
fi
exit 0
EOF_PIPX
chmod +x "${MOCK_BIN}/pipx"

cp -a "${ROOT_DIR}/." "${TMP_ROOT}/setupScript"
SCRIPT="${TMP_ROOT}/setupScript/update-ai-clis.sh"
export HOME="${TMP_HOME}"
export PATH="${MOCK_BIN}:${PATH}"

"${SCRIPT}" init
"${SCRIPT}" sync "${TMP_PROJECT}"
"${SCRIPT}" status "${TMP_PROJECT}" >/dev/null
"${SCRIPT}" reset "${TMP_PROJECT}"
"${SCRIPT}" sync "${TMP_PROJECT}" --dry-run >/dev/null
"${SCRIPT}" reset "${TMP_PROJECT}" --dry-run >/dev/null
"${SCRIPT}" diff "${TMP_PROJECT}" >/dev/null

test -f "${HOME}/.codex/config.toml"
test -f "${HOME}/.claude/settings.json"
test -f "${HOME}/.gemini/settings.json"

node - "${HOME}/.gemini/settings.json" <<'NODE'
const fs = require("fs");
const p = process.argv[2];
const j = JSON.parse(fs.readFileSync(p, "utf8"));
if (!j.mcpServers || typeof j.mcpServers !== "object" || Array.isArray(j.mcpServers)) {
  console.error("mcpServers missing in Gemini settings");
  process.exit(1);
}
NODE

echo "smoke test passed"
