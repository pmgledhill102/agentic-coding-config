### 11. Stale Claude commands/bin files (Tier 1 — surface)

From gather section `stale_claude_files` (silently skipped when `chezmoi` isn't on PATH).

chezmoi only adds and updates target files; it never removes them when source files are renamed or deleted (unless the directory is configured `exact = true`, which has its own destructive risk for user-added files). Result: when a slash command is renamed or retired in the source repo, the OLD file lingers at `~/.claude/commands/` on every machine that ever applied a version where it was present. Claude Code still sees the stale file and lists it as a slash command, so the drift compounds across versions.

The gather computes `chezmoi managed` minus actual contents under `~/.claude/commands/` and `~/.claude/bin/`, and emits any extras (one path per line). Surface them with a one-line `rm` suggestion the user can paste:

```text
2 stale file(s) under ~/.claude/:
  ~/.claude/commands/old-thing.md
  ~/.claude/bin/legacy-script

Suggested: rm ~/.claude/commands/old-thing.md ~/.claude/bin/legacy-script
```

Don't `rm` automatically — the user might be testing an unstaged file, or these may belong to another tool. The check is "fast" (one `chezmoi managed` + two `find`s) so it runs unconditionally per session.

Note this check is a *detector*, not the fix, and it is per-machine: clearing the list here does nothing for the same stale file on any other workstation. The fix is `~/.claude/bin/claude-prune-retired`, which deletes the paths listed in `~/.claude/retired-paths` and is invoked by `dotfiles` after each `chezmoi apply`. So when a stale file turns up here **and** it was retired from `agentic-coding-config`, the durable fix is to add its path to that repo's `home/retired-paths` — not just to `rm` it locally. Files this check surfaces that were *never* managed (left by another tool, or hand-written) don't belong in the list; `rm` those or leave them.

Do **not** propose a `run_onchange_` script in `agentic-coding-config`'s `home/` as an alternative — archive externals aren't source state, so the filename prefix is never interpreted and the script would just deploy as an inert file (see that repo's README, "Deleting a file here does not delete it on machines").
