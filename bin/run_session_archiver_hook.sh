#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(python3 - "$0" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).resolve())
PY
)"
REPO_ROOT="$(cd "$(dirname "${SCRIPT_PATH}")/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/bin/session_archiver_common.sh"

codex_mdfy_load_settings

ARCHIVE_ROOT="${CODEX_SESSION_ARCHIVE_ROOT:-$(codex_mdfy_default_archive_root)}"
ARCHIVE_ROOT="$(codex_mdfy_resolve_path "${ARCHIVE_ROOT}")"

mkdir -p "${ARCHIVE_ROOT}"

exec /usr/bin/env python3 "${REPO_ROOT}/hooks/session_archiver_hook.py" --archive-root "${ARCHIVE_ROOT}"
