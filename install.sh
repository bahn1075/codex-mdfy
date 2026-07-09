#!/usr/bin/env bash
set -euo pipefail

timestamp() {
  date +%Y%m%d%H%M%S
}

default_vault() {
  if [[ -d /app/obsidian ]]; then
    printf '%s\n' /app/obsidian
  elif [[ -d "${HOME}/app/obsidian" ]]; then
    printf '%s\n' "${HOME}/app/obsidian"
  else
    printf '%s\n' "${HOME}/obsidian"
  fi
}

expand_home() {
  local raw
  raw="$1"

  case "${raw}" in
    "~")
      printf '%s\n' "${HOME}"
      ;;
    "~/"*)
      printf '%s/%s\n' "${HOME}" "${raw#~/}"
      ;;
    *)
      printf '%s\n' "${raw}"
      ;;
  esac
}

resolve_dir() {
  local raw
  raw="$(expand_home "$1")"

  if ! mkdir -p "${raw}"; then
    printf 'Failed to create vault directory: %s\n' "${raw}" >&2
    printf 'Check the path and permissions, then run again.\n' >&2
    return 1
  fi
  if ! cd "${raw}"; then
    printf 'Failed to enter vault directory: %s\n' "${raw}" >&2
    return 1
  fi
  pwd -P
}

realpath_if_exists() {
  local path
  local link_target
  local parent
  local name

  path="$1"
  path="$(expand_home "${path}")"

  if [[ -L "${path}" ]]; then
    link_target="$(readlink "${path}")" || return 0
    case "${link_target}" in
      /*)
        realpath_if_exists "${link_target}"
        ;;
      *)
        parent="$(dirname "${path}")"
        realpath_if_exists "${parent}/${link_target}"
        ;;
    esac
    return 0
  fi

  if [[ -d "${path}" ]]; then
    cd "${path}" && pwd -P
    return 0
  fi

  if [[ -e "${path}" ]]; then
    parent="$(dirname "${path}")"
    name="$(basename "${path}")"
    printf '%s/%s\n' "$(cd "${parent}" && pwd -P)" "${name}"
  fi
}

backup_path() {
  local path
  path="$1"
  printf '%s.backup.%s\n' "${path}" "${STAMP}"
}

prompt_product() {
  local requested

  printf 'Session source [1. codex, 2. claude] [1]: ' >&2
  read -r requested || true
  case "${requested}" in
    ""|"1"|"codex"|"Codex"|"CODEX")
      printf '%s\n' "codex"
      ;;
    "2"|"claude"|"Claude"|"CLAUDE")
      printf '%s\n' "claude"
      ;;
    *)
      if [[ "${requested}" == */* ]]; then
        printf 'That looks like a vault path, but this prompt asks for the session source first.\n' >&2
        printf 'Run again and enter 1 for codex or 2 for claude, then enter the vault path at the next prompt.\n' >&2
      fi
      printf 'Unknown selection: %s\n' "${requested}" >&2
      return 1
      ;;
  esac
}

product_home_dir() {
  local product
  product="$1"

  case "${product}" in
    codex)
      printf '%s\n' "${HOME}/.codex"
      ;;
    claude)
      printf '%s\n' "${HOME}/.claude"
      ;;
    *)
      return 1
      ;;
  esac
}

product_source_dir() {
  local product
  product="$1"

  case "${product}" in
    codex)
      printf '%s\n' "${HOME}/.codex/sessions"
      ;;
    claude)
      printf '%s\n' "${HOME}/.claude/projects"
      ;;
    *)
      return 1
      ;;
  esac
}

title_case() {
  local product
  product="$1"

  case "${product}" in
    codex)
      printf '%s\n' "Codex"
      ;;
    claude)
      printf '%s\n' "Claude"
      ;;
    *)
      printf '%s\n' "${product}"
      ;;
  esac
}

move_directory_contents() {
  local source
  local target
  local moved_any
  local item

  source="$1"
  target="$2"
  moved_any=0

  mkdir -p "${target}"

  shopt -s dotglob nullglob
  for item in "${source}"/*; do
    mv "${item}" "${target}/"
    moved_any=1
  done
  shopt -u dotglob nullglob

  if [[ "${moved_any}" -eq 1 ]]; then
    printf 'Moved existing files from %s to %s\n' "${source}" "${target}"
  fi
}

disable_mdfy_hook() {
  local product
  local hook_path
  local hook_realpath
  local backup
  local marker

  product="$1"
  hook_path="$(product_home_dir "${product}")/hooks.json"
  marker="${product}-mdfy"
  if [[ ! -e "${hook_path}" && ! -L "${hook_path}" ]]; then
    return 0
  fi

  hook_realpath="$(realpath_if_exists "${hook_path}")"
  if [[ "${hook_realpath}" == *"/${marker}/"* ]] || grep -q "${marker}" "${hook_path}" 2>/dev/null; then
    backup="$(backup_path "${hook_path}")"
    mv "${hook_path}" "${backup}"
    printf 'Disabled %s hook: %s\n' "${marker}" "${backup}"
  else
    printf 'Left existing non-%s hook in place: %s\n' "${marker}" "${hook_path}"
  fi
}

remove_mdfy_cron() {
  local product
  local current
  local filtered
  local backup
  local marker

  product="$1"
  marker="${product}-mdfy"
  if ! command -v crontab >/dev/null 2>&1; then
    return 0
  fi

  current="$(mktemp)"
  filtered="$(mktemp)"
  crontab -l > "${current}" 2>/dev/null || true

  if ! grep -q "# BEGIN ${marker} daily git sync" "${current}"; then
    rm -f "${current}" "${filtered}"
    return 0
  fi

  mkdir -p "${HOME}/.${marker}"
  backup="${HOME}/.${marker}/crontab.backup.${STAMP}"
  cp "${current}" "${backup}"
  awk -v begin="# BEGIN ${marker} daily git sync" -v end="# END ${marker} daily git sync" '
    $0 == begin {skip = 1; next}
    $0 == end {skip = 0; next}
    skip == 0 {print}
  ' "${current}" > "${filtered}"
  crontab "${filtered}"
  rm -f "${current}" "${filtered}"
  printf 'Removed %s cron block. Backup: %s\n' "${marker}" "${backup}"
}

configure_sessions_link() {
  local product
  local vault
  local target
  local source
  local source_real
  local target_real
  local backup
  local product_label

  product="$1"
  vault="$2"
  target="${vault}/${product}"
  source="$(product_source_dir "${product}")"
  product_label="$(title_case "${product}")"

  mkdir -p "$(product_home_dir "${product}")"

  if [[ -L "${source}" ]]; then
    source_real="$(realpath_if_exists "${source}")"
    target_real="$(realpath_if_exists "${target}")"
    if [[ -n "${source_real}" && -n "${target_real}" && "${source_real}" == "${target_real}" ]]; then
      printf 'Already configured: %s -> %s\n' "${source}" "${target}"
      return 0
    fi
  fi

  if [[ ! -e "${source}" && ! -L "${source}" ]]; then
    mkdir -p "${source}"
  fi

  if [[ -L "${target}" ]]; then
    target_real="$(realpath_if_exists "${target}")"
    source_real="$(realpath_if_exists "${source}")"
    if [[ -n "${target_real}" && -n "${source_real}" && "${target_real}" == "${source_real}" ]]; then
      rm "${target}"
    else
      backup="$(backup_path "${target}")"
      mv "${target}" "${backup}"
      printf 'Backed up existing target symlink: %s\n' "${backup}"
    fi
  elif [[ -e "${target}" ]]; then
    backup="$(backup_path "${target}")"
    mv "${target}" "${backup}"
    printf 'Backed up existing target directory: %s\n' "${backup}"
  fi

  if [[ -L "${source}" ]]; then
    source_real="$(realpath_if_exists "${source}")"
    if [[ -n "${source_real}" && -d "${source_real}" ]]; then
      move_directory_contents "${source_real}" "${target}"
      rmdir "${source_real}" 2>/dev/null || true
    else
      mkdir -p "${target}"
    fi
    rm "${source}"
  else
    mv "${source}" "${target}"
  fi

  ln -s "${target}" "${source}"

  printf '%s sessions now live in: %s\n' "${product_label}" "${target}"
  printf '%s sessions symlink: %s -> %s\n' "${product_label}" "${source}" "$(readlink "${source}")"
}

main() {
  local product
  local suggested
  local requested
  local vault

  STAMP="$(timestamp)"
  product="$(prompt_product)"
  suggested="$(default_vault)"

  printf 'Obsidian vault directory [%s]: ' "${suggested}" >&2
  read -r requested || true
  if [[ -z "${requested}" ]]; then
    requested="${suggested}"
  fi

  vault="$(resolve_dir "${requested}")"

  printf '\nUsing source: %s\n' "${product}"
  printf '\nUsing vault: %s\n' "${vault}"
  configure_sessions_link "${product}" "${vault}"
  disable_mdfy_hook "${product}"
  remove_mdfy_cron "${product}"

  printf '\nDone.\n'
  if git -C "${vault}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '\nGit status for %s path:\n' "${product}"
    git -C "${vault}" status --short -- "${product}"
  else
    printf '\nThe selected vault is not inside a git working tree.\n'
  fi
}

main "$@"
