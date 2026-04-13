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

SYNC_REPO_ROOT="${CODEX_SESSION_SYNC_REPO_ROOT:-${CODEX_SESSION_ARCHIVE_ROOT:-}}"
if [[ -z "${SYNC_REPO_ROOT}" ]]; then
  printf '%s\n' 'No git sync repository has been configured.' >&2
  exit 1
fi

SYNC_REPO_ROOT="$(codex_mdfy_resolve_path "${SYNC_REPO_ROOT}")"
codex_mdfy_assert_sync_repo_ready "${CODEX_SESSION_ARCHIVE_ROOT:-${SYNC_REPO_ROOT}}" "${SYNC_REPO_ROOT}"

BRANCH_NAME="$(git -C "${SYNC_REPO_ROOT}" symbolic-ref --quiet --short HEAD || true)"
if [[ -z "${BRANCH_NAME}" ]]; then
  printf '%s\n' "Skipping git sync because HEAD is detached: ${SYNC_REPO_ROOT}" >&2
  exit 1
fi

STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
printf '[%s] Starting daily sync for %s on branch %s\n' "${STARTED_AT}" "${SYNC_REPO_ROOT}" "${BRANCH_NAME}"

git -C "${SYNC_REPO_ROOT}" add -A
if ! git -C "${SYNC_REPO_ROOT}" diff --cached --quiet --ignore-submodules --; then
  git -C "${SYNC_REPO_ROOT}" commit -m "chore: daily codex-mdfy sync ${STARTED_AT}"
fi

git -C "${SYNC_REPO_ROOT}" pull --rebase --autostash origin "${BRANCH_NAME}"
git -C "${SYNC_REPO_ROOT}" push origin "HEAD:${BRANCH_NAME}"

FINISHED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
printf '[%s] Daily sync completed for %s\n' "${FINISHED_AT}" "${SYNC_REPO_ROOT}"
