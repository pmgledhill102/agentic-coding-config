# Durable machine

True only on a **durable machine** whose `~/.claude/` is managed by chezmoi.
Nothing here applies in a cloud sandbox, which has no chezmoi and a
`~/.claude/` written by the bootstrap.

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

## Testing chezmoi template changes

Verify behaviour in a clean environment before relying on CI:

```sh
HOME=/tmp/chezmoi-test chezmoi init --source <path> --dry-run
```
