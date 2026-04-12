# My Codex Skill

`my-codex-skill` is a small Codex plugin-style project that turns local Codex session transcripts into Markdown archives organized by date and session id.

## What It Includes

- `.codex/hooks.json`: hook configuration discovered by Codex when copied or symlinked into `~/.codex/hooks.json` or `<repo>/.codex/hooks.json`
- `hooks/session_archiver_hook.py`: hook entrypoint that receives Codex hook stdin and refreshes the Markdown archive
- `skills/session-archiver/scripts/render_session_markdown.py`: transcript-to-Markdown renderer used by both hooks and manual export
- `skills/session-archiver/`: the Codex skill for maintaining, installing, and extending the archiver itself
- `config/config.toml.example`: minimum feature flag needed to enable hooks

## Install

1. Clone or copy the repo to `/app/my-codex-skill`, or set `CODEX_SESSION_ARCHIVER_ROOT` to the actual clone path.
2. Add the feature flag from `config/config.toml.example` to `~/.codex/config.toml`.
3. Symlink or copy `.codex/hooks.json` into `~/.codex/hooks.json` for global archiving.
4. Optional: set `CODEX_SESSION_ARCHIVE_ROOT` if you want archives somewhere other than `~/codex-session-archives`.

Example:

```bash
mkdir -p ~/.codex
ln -sf /app/my-codex-skill/.codex/hooks.json ~/.codex/hooks.json
```

If the repo is not stored at `/app/my-codex-skill`, set:

```bash
export CODEX_SESSION_ARCHIVER_ROOT="/absolute/path/to/my-codex-skill"
export CODEX_SESSION_ARCHIVE_ROOT="$HOME/codex-session-archives"
```

## Archive Layout

The hook writes one Markdown file per session:

```text
<archive-root>/<YYYY-MM-DD>/<session-id>/session.md
```

The Markdown includes:

- session metadata such as source, cwd, model, and transcript path
- user and assistant messages
- tool calls
- command executions with exit codes, parsed actions, and command output

## Manual Export

Use the renderer directly to backfill or test a transcript:

```bash
python3 /app/my-codex-skill/skills/session-archiver/scripts/render_session_markdown.py \
  --transcript ~/.codex/sessions/2026/04/12/rollout-2026-04-12T11-24-23-SESSION.jsonl \
  --archive-root ~/codex-session-archives
```

## Notes

- Codex hooks are currently experimental and require `codex_hooks = true`.
- The renderer intentionally suppresses encrypted reasoning and token counters.
- For `exec_command`, the renderer prefers `exec_command_end` events over `function_call_output` to avoid duplicate command output blocks.
