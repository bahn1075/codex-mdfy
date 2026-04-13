---
name: session-archiver
description: Install, debug, or extend transcript-based Codex session archiving that uses hooks plus a Markdown renderer to turn `~/.codex/sessions/*.jsonl` transcripts into `YYYY/MM/DD/codex_<session-id>.md` reports. Use when Codex needs to set up session logging hooks, troubleshoot missing archives, adjust the Markdown format, or export an existing session transcript manually.
---

# Session Archiver

## Overview

Use this skill to maintain the session archiver project or to manually export one Codex transcript into the same Markdown format used by the hooks.

## Workflow

1. Confirm whether the task is installation, debugging, or archive-format work.
2. For installation or debugging, inspect `install.sh`, `.codex/hooks.json`, `bin/run_session_archiver_hook.sh`, and `hooks/session_archiver_hook.py`.
3. For manual export or format changes, use `scripts/render_session_markdown.py` inside this skill.
4. Keep the rendering logic in the skill script and keep the root hook file as a thin entrypoint.

## Install

Run:

```bash
cd /app/codex-mdfy
./install.sh
```

The installer prompts once for the archive root, enables `codex_hooks`, links the skill into `~/.agents/skills/session-archiver`, links the hook runner into `~/.codex-mdfy/run_session_archiver_hook.sh`, and links `.codex/hooks.json` into `~/.codex/hooks.json`.

After installation, use normal `codex` commands. No separate launcher is required.

To change the archive root later, rerun `./install.sh`. The selected top-level directory is saved in `~/.codex-mdfy/session-archiver.env`.

## Manual Export

Run the renderer directly when you need to backfill an existing transcript or validate formatting changes:

```bash
python3 /app/codex-mdfy/skills/session-archiver/scripts/render_session_markdown.py \
  --transcript ~/.codex/sessions/2026/04/12/rollout-2026-04-12T11-24-23-SESSION.jsonl \
  --archive-root ~/codex-session-archives
```

The renderer writes:

```text
<archive-root>/<YYYY>/<MM>/<DD>/codex_<session-id>.md
```

## Debugging

- If no archive file appears, verify `codex_hooks = true`, that `~/.codex/hooks.json` points to this repo's hook config, and that `~/.codex-mdfy/run_session_archiver_hook.sh` exists.
- If the hook runs but the Markdown is stale, inspect `transcript_path` from hook stdin and re-run the renderer manually with that same path.
- If Markdown lands in the wrong directory, inspect `~/.codex-mdfy/session-archiver.env` and rerun `./install.sh` to pick a new archive root.
- If command output is duplicated, prefer the transcript's `exec_command_end` event over `function_call_output` for `exec_command`.
- If you change parsing rules, read `references/transcript-format.md` first and keep the archived section names stable unless the user asked for a format migration.

## Resources

### scripts/

- `render_session_markdown.py` is the source of truth for transcript parsing and Markdown generation.

### references/

- Read `references/transcript-format.md` when changing which event types are included or suppressed.
