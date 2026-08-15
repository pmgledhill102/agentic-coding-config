# Machine-local guidance

True only on a workstation. Nothing here applies in a cloud sandbox, and
this file is deliberately not part of the portable core: a sandbox has no
chezmoi, no `~/.claude/` to be overwritten, and a different shell.

Imported by `CLAUDE.md`. Portable policy lives in `AGENTS.md`.

## `~/.claude/` is generated — do not edit it here

**`~/.claude/` is chezmoi-managed from `pmgledhill102/agentic-coding-config`.**
Do not edit these files directly — chezmoi will overwrite them on the next
apply and the change is lost. This includes `~/.claude/CLAUDE.md` itself,
`~/.claude/AGENTS.md`, this file, `~/.claude/settings.json`, slash commands
under `~/.claude/commands/`, hooks, and scripts under `~/.claude/bin/` —
everything sourced from the `home/` directory of that repo.

To change any of it, open an issue against `agentic-coding-config`; see
"Changing agent config" in `AGENTS.md`. The same applies in reverse — an
`agentic-coding-config` session doesn't get to edit `dotfiles` either.

A merge to that repo does **not** reach this machine immediately. The
external carries a `refreshPeriod` of 168h, so a plain `chezmoi apply` can
re-apply the cached archive: use `chezmoi apply --refresh-externals` (or
`chezmoi update --refresh-externals`) when you specifically need a change
that just merged.

## The interactive shell is zsh

Two differences from bash bite silently, which is why loops belong in a
script file run with `sh` or `bash` rather than composed inline:

- **No word-splitting on unquoted variables.** `set -- $TWO_WORDS` splits
  into two arguments in bash and stays one argument in zsh, so the loop runs
  once with a joined value and downstream parsing fails somewhere unrelated.
  zsh needs `${=VAR}` or a real array
- **`:` is a modifier.** `"$MODEL:generateContent"` flirts with zsh's
  `:g`-style parameter-modifier parsing; write `${MODEL}:generateContent`.
  A bare `$VAR:` in a URL is a trap

Empty arrays also behave differently in zsh under `set -u`.

## Testing chezmoi template changes

Verify behaviour in a clean environment before relying on CI:

```sh
HOME=/tmp/chezmoi-test chezmoi init --source <path> --dry-run
```

## Local scratch space

`/tmp` on macOS is per-user and ephemeral, and is the standard place for
staging multi-line content (issue bodies, PR bodies) before passing it to a
tool via `--body-file`. Note that macOS resolves `/tmp` to `/private/tmp`,
which is why permission rules carry both spellings.
