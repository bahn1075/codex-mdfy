#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load_renderer():
    repo_root = Path(__file__).resolve().parent.parent
    script_dir = repo_root / "skills" / "session-archiver" / "scripts"
    sys.path.insert(0, str(script_dir))
    from render_session_markdown import write_archive  # pylint: disable=import-error

    return write_archive


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Codex hook entrypoint for session archive refreshes."
    )
    parser.add_argument(
        "--archive-root",
        default=None,
        help="Root directory for generated session archives.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload_text = sys.stdin.read().strip()
    if not payload_text:
        return 0

    try:
        payload = json.loads(payload_text)
        transcript_path = payload.get("transcript_path")
        if not transcript_path:
            return 0

        write_archive = load_renderer()
        write_archive(
            transcript_path=Path(transcript_path),
            archive_root=Path(args.archive_root).expanduser() if args.archive_root else None,
            session_id=payload.get("session_id"),
        )
        return 0
    except Exception as exc:  # pragma: no cover - hook failures should not block Codex
        print(
            json.dumps(
                {
                    "continue": True,
                    "systemMessage": f"Session archiver failed: {exc}",
                }
            )
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
