# Strategic review: mission and approach in a cloud-first, multi-provider world

- **Date**: 2026-08-09
- **Tracking**: [#136](https://github.com/pmgledhill102/agentic-coding-config/issues/136)
- **Decisions arising**: [ADR-0014](../../adrs/0014-portable-agent-config-architecture.md)
  (portable architecture), [ADR-0015](../../adrs/0015-tiered-adrs.md) (tiered ADRs)

This review answers the seven questions in #136: what this repo is actually
for, which assets genuinely add value, and whether the approach is forcing
things into a box that no longer fits.

## 1. Verdict up front

**The box is not being forced — the ecosystem moved toward this repo's
model.** Since January, the things this repo bet on (markdown-encoded
workflows, lean policy files, hooks as enforcement, config-as-code) have
become cross-provider standards: AGENTS.md for policy, the Agent Skills
spec (SKILL.md) for workflows, Claude-shaped `hooks.json` for lifecycle
hooks (now also Codex's format), and plugin marketplaces for distribution.

What *has* broken is the **delivery mechanism**. The chezmoi →
`~/.claude/` pipeline only reaches local machines, and most work now
happens in cloud sandboxes that never read it. The content is right; the
pipe is pointed at the wrong place.

## 2. Mission

The repo's contents decompose into four concerns with different
portability needs. Naming them separately is the core clarification —
previous framing ("Claude Code config") bundled them and hid the fact
that only one of the four is inherently machine-local.

| Concern | Examples here | Must reach | Portable form |
| --- | --- | --- | --- |
| **Policy** — how agents should behave | `home/CLAUDE.md` | every provider, every surface | AGENTS.md content core |
| **Workflows** — repeatable procedures | `/setup-*`, `/repo-review`, session lifecycle | every provider, every surface | SKILL.md skills |
| **Enforcement** — quality gates | PreToolUse guards, terraform fmt hook | Claude + Codex (shared `hooks.json` shape); CI remains the backstop everywhere | portable hooks + CI |
| **Machine bootstrap** — local conveniences | permissions allowlist, statusline, MCP wiring | local machines only | chezmoi (shrunken residue) |

Restated mission: **this repo is the portable definition of how I work
with any coding agent, on any surface** — a provider-neutral content core
(policy, skills, hooks) plus thin per-provider adapters — with a small,
explicitly machine-local residue still delivered by chezmoi/dotfiles.

## 2a. Why cloud-first at all (addendum, 2026-08-18)

This review treats "most work now happens in cloud sandboxes" as an
observed fact and never says why. The premise is load-bearing — every
delivery decision since follows from it — so the reasons are recorded
here rather than left implicit.

- **Resilience to a dropped connection.** A cloud session is not running
  on the laptop, so losing wifi or cellular does not lose the work. It
  keeps going while disconnected and is still there on reconnect. This
  matters most on trains and tethered connections, and most of all during
  a long setup script: a 10–15 minute environment build that a local
  session would abandon at the first drop simply continues.

  This is not an edge case here. Regular travel is roughly **three hours
  most weeks** — 40 minutes each way to Manchester, two or three times a
  week — plus a **four-hour round trip every three to four weeks**. That
  is a standing fraction of working time spent on connections that drop
  by design, in tunnels and between masts. A surface that loses a session
  when the signal goes cannot be used for that time at all; a cloud
  session merely stops being watched.

  It is the reason easiest to overlook when comparing the two at a desk
  with good wifi, and the one that decides it in practice.
- **Blast radius.** The session runs in an isolated, single-tenant,
  disposable VM. A destructive mistake costs a container, not a
  workstation, and credentials are handled by a proxy rather than sitting
  in the sandbox.
- **A different, and lower, permissions risk model.** §4.5 demotes the
  granular allowlist honestly: it is bypassed in cloud sessions, and the
  reason that is acceptable is that the thing it protects — a durable
  machine with the user's own files and keys — is not what the agent is
  running on.
- **Parallelism, and not tying up the machine.** Several sessions run at
  once, none of them competing for the laptop's CPU, network, or
  attention.
- **Monitorable from anywhere.** A session can be checked and steered
  from a phone, which only makes sense because it is not tied to a
  terminal.

The costs are real and tracked, not hidden: sandboxes have no user-level
config (#245), miss tools the work needs (#240), and sit behind an egress
policy that blocks documentation and registries (#241). The first two of
those are what this repo exists to close.

**Where this is recorded, and why not in `home/`.** This is rationale, not
policy — it explains a choice rather than instructing an agent. Under
ADR-0018 principle 2 it therefore belongs in repo-meta documentation,
which never deploys and costs no context, rather than in
`home/ephemeral-first.md` where it would load on every turn of every
session forever without changing what any agent does.

## 3. What changed since January (evidence)

Full research is in #136 and its comments; the load-bearing facts:

- **Cloud sessions ignore user-level config** on both Claude and Codex.
  Only repo-committed config, org managed settings, and environment
  setup scripts reach a sandbox. The permissions allowlist, user hooks,
  and user commands are silently absent from most sessions now.
- **Claude plugins reach cloud sessions** when enabled at project scope
  in a committed `.claude/settings.json` (`extraKnownMarketplaces` +
  `enabledPlugins`). This is the one personal-account mechanism that
  closes the cloud gap.
- **Agent Skills (SKILL.md) is an open spec with ~44 clients**, including
  Codex, OpenCode, Cursor, Gemini CLI, and Copilot. The vendor-neutral
  `.agents/skills/` (project) and `~/.agents/skills/` (user) paths are
  scanned natively by Codex, OpenCode, and Gemini CLI.
- **Codex deprecated custom prompts in favour of skills** and auto-
  migrates plugin `commands/` to skills — but rejects `$ARGUMENTS`,
  `$1..$n`, `` !`cmd` `` and `@file` templating as unsupported.
- **Codex adopted Claude's hook model** (same event names, matcher
  groups, `hooks.json`) and **reads Claude's `.claude-plugin/plugin.json`
  manifest**, so one plugin repo can serve both providers.
- **AGENTS.md is read by every major agent except Claude Code**, whose
  documented bridge is a `CLAUDE.md` containing `@AGENTS.md`.
- **No standard exists for permissions**; Claude, Codex and OpenCode
  each have incompatible models.

## 4. Asset-by-asset verdicts

| Asset | Verdict | Summary |
| --- | --- | --- |
| `/setup-*` library (15 provider-neutral commands) | **Keep → convert** | Highest-value content; convert to SKILL.md skills |
| `/repo-review` | **Keep → convert** | Same as above |
| `/start-session`, `/end-session` + `bin/` gather scripts | **Keep → transform** | Surface-aware rework; plugin-relative paths |
| `/retrospective` | **Keep → trim** | Already sandbox-aware; remove residual local assumptions |
| `/promote-journal-inbox` | **Keep as-is** | Local-only by design (runs from the paul-context clone) |
| `home/CLAUDE.md` | **Split** | Portable policy core + Claude adapter + machine-local fragment |
| `settings.json` permissions allowlist | **Demote / freeze** | Local convenience only; stop investing |
| Guard hooks (prepush, precommit, prchecks-wait, terraform fmt) | **Keep → port** | Move to portable `hooks.json` (Claude + Codex shape) |
| Statusline (`cship`), MCP wiring (dotfiles) | **Keep local** | Machine-bootstrap residue |
| chezmoi archive external + `retired-paths` | **Shrink** | Delivers only the residue after migration; retired-paths machinery drives the cutover |

### 4.1 The command library → skills

Fifteen of twenty-one commands contain zero Claude-specific references;
they are provider-neutral procedures that happen to live in a
Claude-shaped directory. Converting them to SKILL.md skills makes them
loadable by every major agent, and skills' progressive-disclosure model
matches the library's own design principle (load only when invoked).

Conversion caveat: heavy `$ARGUMENTS` / `` !`cmd` `` / `@file` templating
does not port to Codex skills. The setup library barely uses these;
where a command does, the skill body should absorb the argument as free
text ("the user names the target repo in their request") rather than
positional substitution.

### 4.2 Session lifecycle

`/start-session` and `/end-session` encode real, hard-won workflow (the
three-tier action model, the gather-script pattern) and stay. Their
transforms: reference scripts via plugin-relative paths instead of
`~/.claude/bin/`, and make machine-specific steps (chezmoi drift check,
stash hygiene) conditional on the surface — a sandbox session has no
chezmoi and no long-lived stashes.

### 4.3 Retrospective — smaller job than feared

The concern in #136 was that `/retrospective` is "highly opinionated
around locally running agents". On inspection that is mostly **already
fixed**: the May–August revisions added the GitHub-Issue journal
fallback for sandboxes, banned direct settings edits in favour of a-c-c
issues, and retired `retros.md`. What remains local-flavoured:

- reads `~/.claude/settings.json` and `~/.claude/projects/<p>/memory/`
  (absent or empty in sandboxes — steps should degrade explicitly);
- routing heuristics assume the dotfiles/a-c-c/paul-context triad
  (fine — that is the actual estate);
- the "approval friction" dimension is meaningless in a sandbox and
  should be skipped there, replaced by a cloud-specific dimension:
  *what config/context was missing from this sandbox session?* — which
  is exactly the signal that feeds this repo's backlog.

### 4.4 Policy file split

`home/CLAUDE.md` mixes three audiences and should split along the
concern boundary:

- **Portable core** (git workflow, work tracking, process guidelines,
  commit/PR style): becomes the AGENTS.md-format policy source, delivered
  to each provider by its adapter.
- **Claude adapter** (MCP tool mappings, `mcp__github__*` preferences):
  Claude-only delivery.
- **Machine-local fragment** ("~/.claude is chezmoi-managed", zsh word-
  splitting, macOS paths): stays chezmoi-deployed, never reaches cloud.

### 4.5 Permissions allowlist — demoted honestly

The ~280-rule allowlist absorbed significant curation effort and is now
bypassed by most sessions (cloud sandboxes run their own permission
model against isolated, disposable infrastructure — the lower risk is
real, not negligence). It is not portable to Codex or OpenCode. Decision
(ADR-0014): keep it as a frozen local-machine convenience; additions
only when local friction actually bites; no proactive curation; the
retrospective's "approval friction" dimension stops feeding it except
for local sessions.

## 5. Tiered ADRs

Per-repo ADRs are among the highest-value habits here, and the tiers
already exist implicitly: `paul-context/decisions/` holds private
cross-repo decisions, a-c-c `adrs/` holds agentic-workflow decisions,
each project repo holds its own. ADR-0015 makes the model explicit —
three tiers (personal-private, user-public, repo), a `Scope` header
field, discovery via each repo's policy file, and cross-tier
supersession rules — without inventing new infrastructure.

## 6. Google Cloud credentials for sandbox agents (the unsolved gap)

No runbook exists for giving a sandbox agent scoped GCP access. The
shape of the solution (to be validated when the runbook is written):

1. **Per-project dedicated service account** for agent use, named so
   audit logs are unambiguous (e.g. `agent-sandbox@<project>`), with the
   minimal role set for the task at hand — never a personal identity or
   an owner-role account.
2. **Short-lived credentials preferred**: mint access tokens via
   `gcloud auth print-access-token --impersonate-service-account` from a
   trusted machine when kicking off work, or use service-account key +
   tight roles + scheduled rotation where a session must self-serve.
   (Cloud sandboxes have no OIDC identity to federate today, so full
   keyless workload-identity federation is not currently available —
   revisit if the platform exposes one.)
3. **Delivery via environment secrets**: the key/token lives in the
   cloud environment's secret env vars, scoped to the one environment
   that needs it — never committed, never pasted into prompts.
4. **Standing revocation path**: document the one-liner to disable the
   SA and the expectation that sandbox-facing SAs are disposable.

## 7. Boundary with dotfiles

dotfiles' mission — a consistent feel across local environments — is
untouched; what shrinks is the *agent config* passing through it.

- **dotfiles keeps**: machine bootstrap, secrets (age), MCP wiring
  (`claude mcp add`), shell/OS config, and the chezmoi external that
  delivers this repo's machine-local residue (permissions, statusline,
  local policy fragment).
- **This repo keeps**: everything portable — policy core, skills, hooks,
  plugin packaging — delivered by plugin install / repo commit rather
  than file-mount.
- **The cutover** uses the existing `retired-paths` machinery: as
  content migrates to the plugin, retire the corresponding
  `~/.claude/commands/*` and `~/.claude/bin/*` paths so machines don't
  see duplicates. The dotfiles-side change (external `include` narrows,
  plugin install added to bootstrap) needs an issue filed in dotfiles
  from a session with access there.

## 8. Decision on #48

**Reshape, then proceed.** #48 predates the Codex/skills findings; the
plugin remains the right distribution vehicle for Claude surfaces, but
its content should be skills-first (not a commands-directory port), its
manifests dual (Claude `.claude-plugin/` + portable `plugin.json` so
Codex can consume the same repo), and its layout anchored on the
vendor-neutral `.agents/skills/` convention. Details in ADR-0014.

## 9. Follow-on work

Filed as sub-issues of #136:

- Reshape and implement plugin distribution (existing #48, re-scoped)
- Convert the provider-neutral command library to SKILL.md skills
- Split `home/CLAUDE.md` into portable core + adapter + local fragment
- Surface-aware rework of session-lifecycle commands; retrospective trim
- Write the sandbox GCP credentials runbook
- Implement tiered ADR conventions (ADR-0015)
- Shrink the chezmoi-deployed surface to the machine-local residue
