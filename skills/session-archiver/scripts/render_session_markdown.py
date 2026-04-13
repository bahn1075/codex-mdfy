#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shlex
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SKIP_USER_PREFIXES = (
    "<environment_context>",
    "# AGENTS.md instructions",
)
SUPPRESSED_FUNCTION_OUTPUTS = {"exec_command", "write_stdin"}


@dataclass
class ArchiveEvent:
    timestamp: str
    kind: str
    title: str
    metadata: dict[str, Any] = field(default_factory=dict)
    body: str = ""


@dataclass
class ParsedTranscript:
    session_id: str
    started_at: str
    last_timestamp: str
    source: str
    originator: str
    cwd: str
    model_provider: str
    cli_version: str
    transcript_path: Path
    events: list[ArchiveEvent]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a Codex session transcript into a Markdown archive."
    )
    parser.add_argument(
        "--transcript", required=True, help="Path to a session JSONL transcript"
    )
    parser.add_argument(
        "--archive-root",
        default=None,
        help="Root output directory. Defaults to ~/codex-session-archives.",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Optional exact Markdown output path. Overrides the default archive layout.",
    )
    parser.add_argument(
        "--session-id",
        default=None,
        help="Override the session id if the transcript is incomplete.",
    )
    return parser.parse_args()


def parse_timestamp(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def stringify_content_blocks(content: list[dict[str, Any]]) -> str:
    parts: list[str] = []
    for block in content:
        text = block.get("text")
        if text:
            parts.append(text.strip())
    return "\n\n".join(part for part in parts if part)


def should_skip_user_message(text: str) -> bool:
    stripped = text.strip()
    return any(stripped.startswith(prefix) for prefix in SKIP_USER_PREFIXES)


def pretty_json(raw: str) -> str:
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return raw.strip()
    return json.dumps(parsed, indent=2, ensure_ascii=False)


def fence(text: str, language: str = "") -> str:
    max_backticks = 0
    current = 0
    for char in text:
        if char == "`":
            current += 1
            max_backticks = max(max_backticks, current)
        else:
            current = 0
    fence_width = max(3, max_backticks + 1)
    tick = "`" * fence_width
    info = language if language else ""
    return f"{tick}{info}\n{text.rstrip()}\n{tick}"


def shell_join(command: Any) -> str:
    if isinstance(command, list):
        return " ".join(shlex.quote(str(part)) for part in command)
    return str(command)


def format_actions(parsed_cmd: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    for item in parsed_cmd:
        action_type = item.get("type", "unknown")
        path = item.get("path") or item.get("name")
        cmd = item.get("cmd")
        if path:
            lines.append(f"- `{action_type}` `{path}`")
        elif cmd:
            lines.append(f"- `{action_type}` `{cmd}`")
        else:
            lines.append(f"- `{action_type}`")
    return "\n".join(lines)


def format_metadata(metadata: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    for key, value in metadata.items():
        if value in (None, "", [], {}):
            continue
        label = key.replace("_", " ").title()
        if isinstance(value, (list, tuple)):
            value_text = ", ".join(f"`{item}`" for item in value)
        else:
            value_text = f"`{value}`"
        lines.append(f"- {label}: {value_text}")
    return lines


def parse_transcript(
    transcript_path: Path, session_id_override: str | None = None
) -> ParsedTranscript:
    events: list[ArchiveEvent] = []
    tool_calls: dict[str, dict[str, Any]] = {}
    session_id = session_id_override or transcript_path.stem
    started_at = ""
    last_timestamp = ""
    source = ""
    originator = ""
    cwd = ""
    model_provider = ""
    cli_version = ""

    with transcript_path.open() as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue

            record = json.loads(line)
            timestamp = record.get("timestamp", "")
            if timestamp:
                last_timestamp = timestamp

            record_type = record.get("type")
            payload = record.get("payload") or {}

            if record_type == "session_meta":
                session_id = payload.get("id") or session_id
                started_at = payload.get("timestamp") or timestamp or started_at
                source = payload.get("source", source)
                originator = payload.get("originator", originator)
                cwd = payload.get("cwd", cwd)
                model_provider = payload.get("model_provider", model_provider)
                cli_version = payload.get("cli_version", cli_version)
                continue

            if record_type == "response_item":
                payload_type = payload.get("type")
                if payload_type == "message":
                    role = payload.get("role")
                    if role not in {"user", "assistant"}:
                        continue
                    text = stringify_content_blocks(payload.get("content") or [])
                    if not text:
                        continue
                    if role == "user" and should_skip_user_message(text):
                        continue

                    phase = payload.get("phase")
                    title = "User Message" if role == "user" else "Assistant Message"
                    metadata = {"role": role}
                    if phase:
                        metadata["phase"] = phase
                    events.append(
                        ArchiveEvent(
                            timestamp=timestamp,
                            kind=role,
                            title=title,
                            metadata=metadata,
                            body=text.strip(),
                        )
                    )
                    continue

                if payload_type == "function_call":
                    call_id = payload.get("call_id", "")
                    name = payload.get("name", "unknown")
                    arguments = payload.get("arguments", "")
                    tool_calls[call_id] = {
                        "name": name,
                        "arguments": arguments,
                    }
                    body = fence(pretty_json(arguments), "json") if arguments else ""
                    events.append(
                        ArchiveEvent(
                            timestamp=timestamp,
                            kind="tool_call",
                            title=f"Tool Call: {name}",
                            metadata={"tool": name, "call_id": call_id},
                            body=body,
                        )
                    )
                    continue

                if payload_type == "function_call_output":
                    call_id = payload.get("call_id", "")
                    call = tool_calls.get(call_id, {})
                    tool_name = call.get("name", "unknown")
                    if tool_name in SUPPRESSED_FUNCTION_OUTPUTS:
                        continue

                    output = payload.get("output", "").strip()
                    body = fence(output, "text") if output else ""
                    events.append(
                        ArchiveEvent(
                            timestamp=timestamp,
                            kind="tool_result",
                            title=f"Tool Output: {tool_name}",
                            metadata={"tool": tool_name, "call_id": call_id},
                            body=body,
                        )
                    )
                    continue

                continue

            if record_type == "event_msg" and payload.get("type") == "exec_command_end":
                command = shell_join(payload.get("command"))
                body_sections: list[str] = []
                if command:
                    body_sections.append("#### Command\n")
                    body_sections.append(fence(command, "bash"))

                parsed_cmd = payload.get("parsed_cmd") or []
                if parsed_cmd:
                    body_sections.append("\n#### Parsed Actions\n")
                    body_sections.append(format_actions(parsed_cmd))

                aggregated_output = (payload.get("aggregated_output") or "").strip()
                if aggregated_output:
                    body_sections.append("\n#### Output\n")
                    body_sections.append(fence(aggregated_output, "text"))

                events.append(
                    ArchiveEvent(
                        timestamp=timestamp,
                        kind="command",
                        title="Command Execution",
                        metadata={
                            "exit_code": payload.get("exit_code"),
                            "cwd": payload.get("cwd"),
                            "call_id": payload.get("call_id"),
                        },
                        body="\n".join(
                            section for section in body_sections if section
                        ).strip(),
                    )
                )

    if not started_at:
        started_at = last_timestamp or datetime.now(timezone.utc).isoformat()

    return ParsedTranscript(
        session_id=session_id,
        started_at=started_at,
        last_timestamp=last_timestamp or started_at,
        source=source or "unknown",
        originator=originator or "unknown",
        cwd=cwd or "unknown",
        model_provider=model_provider or "unknown",
        cli_version=cli_version or "unknown",
        transcript_path=transcript_path,
        events=events,
    )


def resolve_archive_root(archive_root: Path | None) -> Path:
    if archive_root is not None:
        return archive_root.expanduser()
    return Path.home() / "codex-session-archives"


def build_archive_filename(session_id: str) -> str:
    sanitized_session_id = re.sub(r"[^A-Za-z0-9._-]+", "_", session_id).strip("._")
    if not sanitized_session_id:
        sanitized_session_id = "unknown-session"
    if not sanitized_session_id.startswith("codex_"):
        sanitized_session_id = f"codex_{sanitized_session_id}"
    return f"{sanitized_session_id}.md"


def resolve_output_path(
    parsed: ParsedTranscript,
    archive_root: Path | None,
    explicit_output: Path | None = None,
) -> Path:
    if explicit_output is not None:
        return explicit_output.expanduser()

    root = resolve_archive_root(archive_root)
    started = parse_timestamp(parsed.started_at) or datetime.now(timezone.utc)
    return (
        root
        / started.strftime("%Y")
        / started.strftime("%m")
        / started.strftime("%d")
        / build_archive_filename(parsed.session_id)
    )


def render_markdown(parsed: ParsedTranscript, output_path: Path) -> str:
    counts = Counter(event.kind for event in parsed.events)
    tool_names = sorted(
        tool_name
        for event in parsed.events
        if event.kind in {"tool_call", "tool_result"}
        for tool_name in [event.metadata.get("tool")]
        if isinstance(tool_name, str) and tool_name
    )
    non_zero_exits = sum(
        1
        for event in parsed.events
        if event.kind == "command" and event.metadata.get("exit_code") not in (None, 0)
    )

    lines = [
        "# Codex Session Archive",
        "",
        "## Session",
        f"- Session Id: `{parsed.session_id}`",
        f"- Source: `{parsed.source}`",
        f"- Originator: `{parsed.originator}`",
        f"- Started At: `{parsed.started_at}`",
        f"- Last Event At: `{parsed.last_timestamp}`",
        f"- Working Directory: `{parsed.cwd}`",
        f"- Model Provider: `{parsed.model_provider}`",
        f"- Cli Version: `{parsed.cli_version}`",
        f"- Transcript Path: `{parsed.transcript_path}`",
        f"- Archive Path: `{output_path}`",
        "",
        "## Summary",
        f"- User Messages: `{counts.get('user', 0)}`",
        f"- Assistant Messages: `{counts.get('assistant', 0)}`",
        f"- Tool Calls: `{counts.get('tool_call', 0)}`",
        f"- Tool Outputs: `{counts.get('tool_result', 0)}`",
        f"- Command Executions: `{counts.get('command', 0)}`",
        f"- Non-zero Command Exits: `{non_zero_exits}`",
        f"- Tools Used: {', '.join(f'`{name}`' for name in tool_names) if tool_names else '`none`'}",
        "",
        "## Timeline",
        "",
    ]

    for event in parsed.events:
        lines.append(f"### {event.timestamp} · {event.title}")
        metadata_lines = format_metadata(event.metadata)
        if metadata_lines:
            lines.extend(metadata_lines)
        if event.body:
            if metadata_lines:
                lines.append("")
            lines.append(event.body.rstrip())
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def write_archive(
    transcript_path: Path,
    archive_root: Path | None = None,
    output_path: Path | None = None,
    session_id: str | None = None,
) -> Path:
    parsed = parse_transcript(transcript_path, session_id_override=session_id)
    destination = resolve_output_path(
        parsed, archive_root=archive_root, explicit_output=output_path
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(render_markdown(parsed, destination))
    return destination


def main() -> int:
    args = parse_args()
    destination = write_archive(
        transcript_path=Path(args.transcript).expanduser(),
        archive_root=Path(args.archive_root).expanduser()
        if args.archive_root
        else None,
        output_path=Path(args.output).expanduser() if args.output else None,
        session_id=args.session_id,
    )
    print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
