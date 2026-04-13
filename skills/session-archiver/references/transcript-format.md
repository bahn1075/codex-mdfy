# Transcript Format Notes

The session archiver reads Codex JSONL transcripts from `~/.codex/sessions/...`.

## Included Record Types

- `session_meta`
- `response_item` user messages
- `response_item` assistant messages
- `response_item` `function_call`
- `response_item` `function_call_output` for non-shell tools
- `event_msg` `exec_command_end`

## Suppressed Record Types

- encrypted reasoning payloads
- token counters
- duplicate `agent_message` commentary events
- `function_call_output` for `exec_command` and `write_stdin` because `exec_command_end` is richer
- bootstrap messages such as `<environment_context>` and `# AGENTS.md instructions`

## Archive Path

The renderer writes:

```text
<archive-root>/<YYYY>/<MM>/<DD>/codex_<session-id>.md
```

The date key comes from `session_meta.payload.timestamp` when available and falls back to the current date if the transcript is malformed.
