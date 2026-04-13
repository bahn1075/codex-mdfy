#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(python3 - "$0" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).resolve())
PY
)"
REPO_ROOT="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/bin/session_archiver_common.sh"

codex_mdfy_load_settings

ARCHIVE_ROOT="$(codex_mdfy_prompt_archive_root)"
ARCHIVE_ROOT="$(codex_mdfy_resolve_path "${ARCHIVE_ROOT}")"

mkdir -p "${ARCHIVE_ROOT}"

codex_mdfy_write_settings "${ARCHIVE_ROOT}"
codex_mdfy_install_runtime_links "${REPO_ROOT}"
codex_mdfy_remove_legacy_launcher
codex_mdfy_enable_hooks_feature

printf '\n%s\n' 'codex-mdfy installation complete.'
printf 'Archive root: %s\n' "${ARCHIVE_ROOT}"
printf 'Skill link: %s\n' "${HOME}/.agents/skills/session-archiver"
printf 'Hook runner: %s\n' "${HOME}/.codex-mdfy/run_session_archiver_hook.sh"
printf 'Hooks config: %s\n' "${HOME}/.codex/hooks.json"
printf '\n%s\n' 'Start Codex with:'
printf '  %s\n' 'codex'
