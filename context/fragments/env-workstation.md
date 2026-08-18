# Machine-local guidance

True only on a **macOS workstation running zsh**, with `~/.claude/` managed
by chezmoi. Nothing here applies in a cloud sandbox, which has no chezmoi, a
`~/.claude/` written by the bootstrap, and a different shell. This fragment is
composed only into workstation profiles; the composition guard in
`tests/compose-context.py` fails the build if it reaches a sandbox one.

## Windows is out of scope, via WSL

Windows is not a target and no accommodation for it belongs anywhere in this
repo — no PowerShell, no `cmd`, no Windows paths, no CRLF handling. **If
Windows is ever needed it is via WSL running Ubuntu**, which is the same
userland as the cloud sandboxes, so it costs a new environment fragment rather
than a second dialect running through every script.

That constraint is what keeps the surface count at two: **macOS and Ubuntu
24.04**. Both cloud harnesses are Ubuntu 24.04 — Claude's sandbox and Codex's
`codex-universal`, which is `FROM ubuntu:24.04`.

Note for whoever adds that fragment: this file currently mixes two things that
happen to correlate today — **persistence and delivery** (durable, chezmoi
manages `~/.claude/`) and **OS and shell** (macOS, zsh, BSD userland). A WSL
profile is the case that breaks the correlation, being durable and
chezmoi-managed but Ubuntu and GNU. It would want the first half of this file
and not the second. Splitting the environment axis into those two
sub-dimensions is deliberately *not* done now, because nothing needs it; the
seam is named so the split is a refactor rather than a rediscovery.

## `~/.claude/` is generated — do not edit it here

**`~/.claude/` is chezmoi-managed from `pmgledhill102/agentic-coding-config`.**
Do not edit these files directly — chezmoi will overwrite them on the next
apply and the change is lost. That covers `~/.claude/settings.json`, slash
commands under `~/.claude/commands/`, hooks, and scripts under
`~/.claude/bin/` — everything sourced from the `home/` directory of that repo.

`~/.claude/CLAUDE.md` and `~/.claude/AGENTS.md`, including the text you are
reading, are worse than merely deployed: they are **generated**, composed from
fragments in `context/fragments/` by `tests/compose-context.py`. Editing one
loses the change twice — chezmoi overwrites the file, and CI would have
rejected it anyway for not matching its fragments. Edit the fragment.

To change any of it, open an issue against `agentic-coding-config`; see
"Changing agent config" in `AGENTS.md`. The same applies in reverse — an
`agentic-coding-config` session doesn't get to edit `dotfiles` either.

A merge to that repo does **not** reach this machine immediately. The
external carries a `refreshPeriod` of 168h, so a plain `chezmoi apply` can
re-apply the cached archive.

**`dotup` already handles this** — it runs `chezmoi update
--refresh-externals`, which is pull plus apply with the cache bypassed, and
it is the command to reach for after a merge. Drop to
`chezmoi apply --refresh-externals` only when you want the apply without
the rest of what `dotup` does (Oh My Zsh, plugins, Starship).

The same apply is what removes retired files: `dotup` triggers dotfiles'
post-apply hook, which runs `~/.claude/bin/claude-prune-retired` against
the `retired-paths` list that just arrived through the external.

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
