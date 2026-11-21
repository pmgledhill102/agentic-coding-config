# Codex adapter

Codex-specific guidance. The portable policy and the environment guidance are
composed in from their own fragments; this section is only what would be
meaningless to another provider.

## This file is composed whole

Codex layers `AGENTS.md` files: a global one under its home directory, then
one per directory from the project root down. Each is read as-is, so this
policy is composed into one — the core, the environment, and this section.

That is why composition emits complete files rather than references. Codex
does not support `@file` imports, nor `$ARGUMENTS`, `$1..$n` or `` !`cmd` ``
templating. A line like `@ephemeral-first.md` reaches Codex as literal text
and the content it names is silently lost, which is exactly what used to
happen here — see ADR-0018.

## Skills

Skills are read from `~/.agents/skills/`, the vendor-neutral location, scanned
natively. A skill installed there is discoverable without being announced.

Codex has deprecated custom prompts in favour of skills, so a skill is the
only unit worth authoring — which is the same conclusion ADR-0018 principle 3
reaches from the other direction.

## GitHub operations

The `mcp__github__*` tools named in the Claude adapter do not exist here; where
a skill names one, the `gh` equivalent beside it applies. Check `command -v gh`
first: the cloud bootstrap installs none for the Codex cloud profile.

## Hooks

Codex shares the hook JSON shape and a core set of event names with Claude
Code, but not the file location, the handler types or the trust model.
