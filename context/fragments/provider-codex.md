# Codex adapter

Codex-specific guidance. The portable policy and the environment guidance are
composed in from their own fragments; this section is only what would be
meaningless to another provider.

## This file is the whole instruction set

Codex reads `AGENTS.md`. There is no second file it also loads, so everything
it needs is composed into this one — the portable core, the environment
fragment, and this section.

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

Use the `gh` CLI. The `mcp__github__*` tools named in the Claude adapter do
not exist here; where a skill's text names one, the `gh` equivalent alongside
it is the instruction that applies.

## Hooks

Codex uses the same `hooks.json` shape as Claude Code — same event names, same
matcher groups — so a hook authored once works on both.
