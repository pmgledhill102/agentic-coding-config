# ADR-0018: Composing agent context per surface — profiles, tiers, one mechanism

- **Status**: Proposed (2026-08-18)
- **Date**: 2026-08-18
- **Tags**: architecture, portability, context, skills, claude-code, codex
- **Scope**: user (applies to all personal repos and agent surfaces)

## Context

[ADR-0016](0016-capability-delivery-principles.md) settled *where* a
capability should live. It did not say how the **content** that reaches a
session is assembled, and the estate has since accumulated three
symptoms of that gap.

**Cloud sandboxes get no policy at all.** Verified 2026-08-17: `ls
~/.claude/*.md` is empty in a sandbox. The 221 lines of portable policy
in `home/AGENTS.md` and `home/ephemeral-first.md` reach workstations via
chezmoi and nothing else. Sessions on what is now the primary surface run
with whatever the opened repo happens to commit.

**Content branches at runtime on which surface it is running.** The
session commands ask `command -v chezmoi` and route on the answer:

```text
home/commands/start-session.md     8 surface conditionals
home/commands/end-session.md      11
home/commands/retrospective.md    16
```

Each branch is text that every session reads and most sessions cannot
use. A sandbox pays context for workstation instructions and then has to
correctly decide to ignore them — a decision it can get wrong, and
[#239](https://github.com/pmgledhill102/agentic-coding-config/issues/239)
is what that looks like when it does.

**Two mechanisms carry the same payload.** `home/commands/*.md` and
`home/skills/*/SKILL.md` both register `/name` and behave identically —
`cloud/bootstrap.sh` says so in a comment and deletes the duplicate
registration it would otherwise create. 17 of 21 commands already have a
skill twin, kept in step by a test that documents its own retirement.

Underneath all three is one question this ADR answers: **when a statement
must hold on some surfaces and not others, what resolves the
difference — the agent at runtime, or the delivery at build time?**

One fact makes the answer available. ADR-0016 established that a
container-created `~/.claude/skills` is read, symlinks included, on both
Claude Code and Codex. A canary on 2026-08-18 extended that to policy: a
`~/.claude/CLAUDE.md` written 37 minutes after session start was loaded
on resume, announced as *"user's private global instructions for all
projects"*. Per-surface policy delivery is therefore possible, which is
what makes per-surface composition worth designing.

## Decision

Adopt seven principles for composing and delivering agent context.

### 1. Determinism over conditionals

**Environment differences are resolved when content is delivered, not
when it is read.** A sandbox receives text that is true in a sandbox. A
workstation receives text that is true on a workstation. Neither receives
a conditional describing the other.

This is binding for always-loaded policy and strong for everything else.
The reasoning differs by tier, which is why they are separated:

- In policy, a conditional costs context on **every turn of every session
  for the rest of time**, and the surface it does not apply to pays that
  cost permanently.
- In a procedure, the cost is smaller but the risk is larger: a branch is
  a decision the agent can take wrongly, and a wrong branch on a
  destructive step is worse than a missing instruction.

The corollary is that runtime surface-detection — `command -v chezmoi`
and its relatives — is a smell in content. It is legitimate in a
*script*, which is code and has no context cost; it is not legitimate in
prose the model reads.

### 2. Tier every statement by what it costs to load

There are three tiers, and they differ by an order of magnitude in cost:

| Tier | Loaded | Cost |
| ---- | ------ | ---- |
| Policy (`AGENTS.md` / `CLAUDE.md`) | in full, every session | highest — permanent |
| Skill description | one line, every session | low, but multiplied by skill count |
| Skill body | only when the skill is used | ~zero until used |

**A statement's tier is chosen deliberately.** Policy is for what must
hold every turn regardless of task. Anything procedural belongs in a
skill body, where it costs nothing until needed.

This reframes the usual question. "Which file does this go in" is
downstream of "how often must this be true", and getting the second right
makes the first mechanical. It is also the answer to the context budget:
Claude Code targets under 200 lines of always-loaded policy, and the
portable core plus principles already exceeds it — not because the
content is wrong, but because some of it is procedure sitting in the
policy tier.

### 3. One mechanism: skills

**Skills are the unit. `home/commands/` is retired.** Slash commands and
skills register identically; skills additionally carry frontmatter that
lets the model invoke them unprompted, bundle adjacent files, and are the
cross-provider standard rather than a per-vendor directory.

Keeping both means every content change is made twice — which is exactly
why `tests/skills-match-commands.py` exists, and that test is scaffolding
for a migration, not a permanent fixture.

### 4. Fragments are the source; delivered artefacts are derived

Content is authored as **fragments** — a portable core, a provider
fragment, an environment fragment. What lands on a surface is
**composed** from them by a single generator, committed, and checked in
CI.

The generator is one program. Composition must not live in the
installers: `cloud/bootstrap.sh` and the chezmoi path would then hold two
implementations of the same logic, delivered by different routes, drifting
independently. That is the failure this repo keeps meeting, one level up.

Committing the composed output rather than assembling at install time
also means **the artefact a surface receives is readable in the repo**,
which matters when the question is "why did the agent believe that".

### 5. Profiles compose from axes, not from names

Surfaces vary along two independent axes:

- **provider** — Claude Code, Codex, OpenCode: tool names, MCP servers,
  invocation spellings
- **environment** — workstation, cloud sandbox: whether chezmoi manages
  `~/.claude`, whether a credential broker exists, what is on `PATH`

A profile is a **point** in that space, not a hand-written file. One core
plus two provider fragments plus two environment fragments composes four
profiles; adding a provider costs one fragment, not one file per
environment. Naming profiles directly — `agents-claude-sandbox.md`,
`agents-codex-sandbox.md` — restates the environment half once per
provider and grows multiplicatively.

`home/local-machine.md` is already an environment fragment. It is only
reachable through `home/CLAUDE.md`, which is why shipping that file
verbatim to a sandbox would inject chezmoi instructions into the one
surface with no chezmoi. The axis split makes that structurally
impossible rather than a thing to remember.

### 6. No delivery assumptions in portable text

Restated from ADR-0016 principle 3 and now load-bearing: content names
what it needs, never where the delivery put it. The `~/.claude/bin/...`
paths in the broker skill are the standing example, and
[#234](https://github.com/pmgledhill102/agentic-coding-config/issues/234)
is the cost.

Under principle 1 this gets sharper. Deterministic delivery removes the
excuse for a path conditional: if a path genuinely differs by surface, it
belongs in the environment fragment, resolved at composition.

### 7. Every profile is built and verified in CI

Deterministic delivery trades runtime adaptability for build-time
correctness. **That is only a good trade if something checks the build.**

A conditional, for all its cost, degrades visibly — the wrong branch runs
and someone notices. A profile that was composed wrongly, or from a stale
fragment, is silent: it is only wrong on a surface, and a surface nobody
used this week is a surface nobody is watching.

So CI composes **every** profile on every change and asserts the
committed outputs match. Additionally, and specifically:

- every committed profile matches what the generator produces from the
  current fragments
- no sandbox profile transitively includes a workstation-only fragment
- every composed policy artefact is reported with its line count, so the
  always-loaded budget is a number in the build rather than a surprise

This principle is the price of the other six. Without it, principle 1
converts loud failures into quiet ones.

## Consequences

### Positive

- A sandbox session reads only statements that are true in a sandbox.
  Context spent on the other surface's instructions goes to zero.
- The single biggest reliability gap closes: `start-session`,
  `end-session` and `retrospective` become deliverable, in a form
  appropriate to each surface, rather than one text hedging across all of
  them.
- Adding a provider is one fragment and a CI row.
- The always-loaded budget becomes measurable and enforced rather than
  discovered when adherence degrades.
- Retiring `home/commands/` halves the edit surface for every content
  change and removes a test that exists only to police duplication.

### Negative / trade-offs

- **This reverses part of [#139](https://github.com/pmgledhill102/agentic-coding-config/issues/139).**
  The surface-aware rework of the session commands — `command -v
  chezmoi`, the `chezmoi-unavailable` sentinel, the silent-skip states —
  is the runtime-detection pattern principle 1 replaces. That work was
  correct under the constraint that one text had to serve every surface.
  Removing the constraint makes it unnecessary, not wrong, and it should
  be unwound deliberately rather than left as two overlapping mechanisms.
- **Generated files in the tree.** Composed artefacts are committed, so
  reviewers see machine-written diffs alongside fragment edits. Mitigated
  by CI failing on a stale artefact, which makes the diff mandatory
  rather than optional.
- **Profiles multiply.** Four today, more as providers and environments
  appear. The axes bound the growth but do not stop it, and ADR-0016
  already flagged environment proliferation as a thing to watch.
- **A fragment used by one profile is exercised by one surface.** Rot is
  invisible without principle 7, and principle 7 checks composition, not
  truth: CI can prove the sandbox profile was built correctly and cannot
  prove its contents are still accurate. That remains a human review.
- **The content review is unavoidable and is not small.** Splitting
  content by surface requires deciding, line by line, which surface each
  line is true on. Much of `home/` predates the cloud surface entirely.

### Explicitly not decided here

Whether the AGENTS.md format supports any import mechanism, and where a
user-level `AGENTS.md` lives for Codex, are unverified — `agents.md` is
blocked by the sandbox egress policy
([#241](https://github.com/pmgledhill102/agentic-coding-config/issues/241)).
This ADR is written so the answer does not matter: composition produces
complete files, so no consumer needs import support. If it turns out
imports are available, they are an optimisation, not a change of shape.

## Alternatives considered

**Compose by import (`@fragment.md`).** Claude Code expands `@path`
imports at launch, four hops deep, so a three-line `CLAUDE.md` could pull
in core plus fragments with no generator at all. Rejected as the general
mechanism because it is, as far as is known, Claude-only: an `AGENTS.md`
containing `@agents-core.md` reaches Codex as literal text, and fails
silently rather than loudly. Retained as a possible Claude-side
simplification once the AGENTS.md question above is answered.

**Assemble at install time in each installer.** `bootstrap.sh` and the
chezmoi path each concatenate fragments. Rejected: two implementations of
one logic, on two delivery routes, with no shared test — and the obvious
fix, a shared script, has to be delivered to both, which is the problem
it was meant to solve.

**Symlink `AGENTS.md` and `CLAUDE.md` to one master.** Works only while
the two files are byte-identical. `CLAUDE.md` carries the GitHub MCP
mapping table, which is meaningless to other providers, so they diverge
immediately. Symlinks remain the right tool *within* a profile — one file
serving several vendor paths, as ADR-0016 confirmed for skills.

**Keep runtime conditionals; do nothing.** Rejected. It is the current
state, it costs context on every surface permanently, and it has already
produced one failure where a session could not tell which half of a
document applied to it.

## References

- [ADR-0014](0014-portable-agent-config-architecture.md) — the mechanisms
  being composed
- [ADR-0015](0015-tiered-adrs.md) — tier conventions; this is a user-tier
  decision
- [ADR-0016](0016-capability-delivery-principles.md) — where capability
  lives; principle 6 here restates its principle 3, and its container-created
  `~/.claude` findings are what make this feasible
- #238, #239, #245 — the delivery gaps this is the framework for
- #246 — staleness; principle 7 is build-time correctness, #246 is
  deployed-time freshness, and they are different problems
- #247, #142, #48 — content review, chezmoi shrink, and the commands
  retirement that principle 3 completes
