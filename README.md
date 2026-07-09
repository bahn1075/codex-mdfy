# codex-mdfy

`codex-mdfy` now does one small thing: it moves native Codex or Claude session
directories into an Obsidian vault so the raw transcript files can be tracked by
that vault's git repository.

No Codex hooks are installed. No Markdown renderer is used. No background sync
job is registered.

## Layout

After running the installer, the layout is:

```text
<obsidian-vault>/codex/        # real directory, visible to git
~/.codex/sessions -> <obsidian-vault>/codex

<obsidian-vault>/claude/       # real directory, visible to git
~/.claude/projects -> <obsidian-vault>/claude
```

This direction matters. Git tracks files inside real directories, but it does
not follow a directory symlink and add the files behind it. Therefore
`<obsidian-vault>/codex` or `<obsidian-vault>/claude` must be the real
directory.

## Run

```bash
cd /app/codex-mdfy
./install.sh
```

The script first asks which session source to configure:

```text
1. codex
2. claude
```

Then it asks for the Obsidian vault directory. If `/app/obsidian` exists, it is
offered as the default.

## What The Script Does

1. Creates the selected vault directory if needed.
2. Backs up any existing target path before replacing it.
3. Physically moves the selected source directory to the target path:
   - Codex: `~/.codex/sessions` to `<vault>/codex`
   - Claude: `~/.claude/projects` to `<vault>/claude`
4. If the selected source is already a symlink to a different directory, moves
   that real directory's contents into the target before replacing the symlink.
5. Creates the source symlink:
   - Codex: `~/.codex/sessions -> <vault>/codex`
   - Claude: `~/.claude/projects -> <vault>/claude`
6. Disables the old matching `*-mdfy` hook if it is still installed.
7. Removes the old matching `*-mdfy` cron sync block if it is still installed.
8. Prints `git status --short -- <codex|claude>` when the vault is a git working
   tree.

## Verify

After running the script:

```bash
ls -ld ~/.codex/sessions /app/obsidian/codex
find /app/obsidian/codex -name '*.jsonl' | tail
git -C /app/obsidian status --short -- codex
```

For Claude:

```bash
ls -ld ~/.claude/projects /app/obsidian/claude
find /app/obsidian/claude -name '*.jsonl' | tail
git -C /app/obsidian status --short -- claude
```

Expected Codex shape:

```text
/app/obsidian/codex           # directory
~/.codex/sessions -> /app/obsidian/codex
```

Expected Claude shape:

```text
/app/obsidian/claude          # directory
~/.claude/projects -> /app/obsidian/claude
```

The `git status` output should show the raw transcript files under `codex/` or
`claude/` as normal git-tracked candidates.
