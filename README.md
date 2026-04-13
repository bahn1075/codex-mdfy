# codex-mdfy

`codex-mdfy` turns local Codex session transcripts into Markdown files and installs the supporting Codex skill and hooks with a single shell command.

## What It Includes

- `install.sh`: one-click installer that enables hooks, installs the skill link, installs the hook runner, and saves the default archive root
- `bin/run_session_archiver_hook.sh`: non-interactive hook runner installed under `~/.codex-mdfy/`
- `.codex/hooks.json`: Codex hook configuration that delegates to the installed hook runner
- `hooks/session_archiver_hook.py`: thin Python hook entrypoint that receives Codex hook stdin and refreshes the Markdown archive
- `skills/session-archiver/scripts/render_session_markdown.py`: transcript-to-Markdown renderer used by both hooks and manual export
- `skills/session-archiver/`: the Codex skill that gets linked into `~/.agents/skills/session-archiver`

## One-Click Install

Run:

```bash
cd /app/codex-mdfy
./install.sh
```

The installer will:

1. Ask where Markdown session histories should be stored.
2. Save that directory once as the archive top-level root.
3. Enable the `codex_hooks` feature when `codex` is available.
4. Link the skill into `~/.agents/skills/session-archiver`.
5. Link the hook runner into `~/.codex-mdfy/run_session_archiver_hook.sh`.
6. Link `.codex/hooks.json` into `~/.codex/hooks.json`.

After installation, keep using plain `codex` as usual.

## Archive Root Changes

The archive root is requested once during installation and persisted in `~/.codex-mdfy/session-archiver.env`.

To change it later, rerun:

```bash
cd /app/codex-mdfy
./install.sh
```

## Archive Layout

Each session is written to this tree:

```text
<archive-root>/
├── YYYY
│   └── MM
│       └── DD
│           └── codex_<session-id>.md
```

The Markdown includes:

- session metadata such as source, cwd, model, and transcript path
- user and assistant messages
- tool calls
- command executions with exit codes, parsed actions, and command output

## Manual Export

Use the renderer directly to backfill or test a transcript:

```bash
python3 /app/codex-mdfy/skills/session-archiver/scripts/render_session_markdown.py \
  --transcript ~/.codex/sessions/2026/04/12/rollout-2026-04-12T11-24-23-SESSION.jsonl \
  --archive-root ~/codex-session-archives
```

The manual renderer follows the same `YYYY/MM/DD/codex_<session-id>.md` layout unless you pass `--output`.

## Notes

- The archived root is persisted in `~/.codex-mdfy/session-archiver.env`.
- `~/.codex/hooks.json` calls the installed hook runner, so the repo can live outside `/app/`.
- The renderer intentionally suppresses encrypted reasoning and token counters.
- For `exec_command`, the renderer prefers `exec_command_end` events over `function_call_output` to avoid duplicate command output blocks.
