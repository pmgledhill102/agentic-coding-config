# ADR-0016: Where capability lives — environment, repo, or content

- **Status**: Accepted (2026-08-13), validated on Claude Code and Codex
- **Date**: 2026-08-13
- **Tags**: architecture, cloud, plugins, portability, claude-code, codex
- **Scope**: user (applies to all personal repos and agent surfaces)

## Context

[ADR-0014](0014-portable-agent-config-architecture.md) chose mechanisms:
skills as the portable unit, an AGENTS.md policy core, a dual-manifest
plugin, and — for cloud sessions — project-scope enablement committed to
each repo's `.claude/settings.json`.

That decision is sound for what it was aimed at. But it answers "how do
we distribute agent config" without asking "is this thing agent config
at all", and the first real cloud-sandbox exercise (2026-08-12, the GCP
credential broker in `cloud-run-behind-apix`) showed the gap. Making a
repo able to reach Google Cloud from a sandbox needed:

- `gcloud` installed in the VM
- `dl.google.com` and the broker host on the network allowlist
- `CREDENTIAL_BROKER_URL` and `CREDENTIAL_BROKER_REQUEST_KEY` set
- the broker client helper and its skill available to the session

Only the last is agent config. The rest are properties of the *machine*
and its *network*, and none of them varies by repository. Following
ADR-0014 point 3 literally would have committed Claude-proprietary JSON
into a repo — one that also carries an `AGENTS.md` for other providers —
in order to configure something that is not about that repo.

The question the estate keeps re-deriving, once per surface, is: **when a
session needs a capability, where should the thing that grants it live?**
This ADR answers that so the next mechanism can be chosen without
re-litigating the last one.

## Decision

Adopt six principles, applied in order, when deciding where any piece of
agent-enabling configuration belongs.

### 1. Adding a capability changes nothing in the repo

Working in a coding agent on one of these repos should come with cloud
capabilities, and **acquiring them must be invisible to the repo**. No
committed file records that sessions here can reach Google Cloud, and
none is edited to give them that reach.

This is the claim the other four serve. Three reasons it is more than
tidiness:

- **Capability is per-session, not per-project.** One sandbox has GCP
  access, a collaborator's does not, a laptop has it by another route.
  A repo asserting "sessions here have GCP" states something true for
  some people, some of the time.
- **It is a runtime property in a design-time artefact.** The repo
  outlives the capability and nothing updates it when the environment
  changes, so it goes stale in silence — the same failure as a vendored
  copy, one level up.
- **It is the precondition for working across providers.** An
  `extraKnownMarketplaces` block is Claude-only; committed to a repo a
  Codex session also reads, it is dead weight that makes the repo *look*
  vendor-specific when it is not. Capability supplied by the environment
  is the only form every provider can express, because each supplies it
  its own way and the repo never learns which.

**A repo may declare a need; it must not implement the capability.** A
line in `AGENTS.md` saying tasks here need GCP access via the broker is
prose — portable, vendor-neutral, and it does not break when the
mechanism changes. What must not appear is anything that *provides* the
access: marketplace declarations, a vendored helper, credentials, paths.

Declaring the need is also the answer to the obvious objection, that an
invisible capability is undiscoverable. The requirement stays visible.
Only its implementation moves.

### 2. Classify before choosing a mechanism

Every requirement is either an **environment capability** or **project
configuration**:

- **Environment capability** — a property of the machine, its network, or
  the credentials obtainable from it. It does not vary by repository, and
  two repos needing it want it *identical*. Toolchains, network reach,
  credential brokering, OS packages.
- **Project configuration** — genuinely specific to one repository. Its
  conventions, its pre-approved commands, which skills it uses, its
  build and test commands.

The classification determines the mechanism, and it is the step that was
missing:

| Concern | Lives in | Reaches cloud via |
| ------- | -------- | ----------------- |
| Toolchain, OS packages, network allowlist | Cloud environment config | Setup script + allowed domains, deferring to a versioned script |
| Credentials and broker endpoints | Cloud environment config | Environment variables |
| Portable skills and policy | This repo, delivered as content | Plugin, or setup-script placement |
| Repo conventions, permissions, build commands | The repo's own `.claude/` | Part of the clone |

A repo pointed at a `gcp-enabled` environment gains GCP access with
**zero files committed**. That is the correct outcome, and ADR-0014's
route could not express it.

Concretely, per surface:

| Surface | Capability arrives via | Repo footprint |
| ------- | ---------------------- | -------------- |
| Claude Code cloud sandbox | setup script → `cloud/bootstrap.sh` → `~/.claude/skills` | none |
| Codex cloud sandbox | setup script → `cloud/bootstrap.sh` → `~/.agents/skills` | none |
| Local terminal (macOS) | chezmoi → `~/.claude`, plus the refresh daemon | none |
| Self-hosted sandbox | superseded by the vendors' own | n/a |

Note the column headings carefully: they say which surface **owns** a
concern, not which surface holds its **implementation**. The first draft
of this ADR was read — by its own author — as licence to put `apt-get`
lines in a setup script, which principle 6 then forbids two sections
later. The environment *triggers* a toolchain install by choosing to
call the bootstrap, and by what it passes; what gets installed stays
versioned here with everything else.

### 3. Provider-specific coupling belongs on provider-specific surfaces

Prefer the surface that is *already* provider-specific, and prefer one
outside version control where a choice exists.

The Claude Code cloud environment config is Claude-only and lives outside
any repository, so Claude-only plumbing costs nothing there. Committing
`extraKnownMarketplaces` into a repo does the opposite: it plants
vendor-proprietary configuration in a directory that Codex, OpenCode and
Cursor also read, to solve a problem only one vendor has.

This does not forbid the plugin route. It scopes it: use it for **project
configuration**, where per-repo declaration is the point, and not for
**environment capability**, where it is a tax.

### 4. Portable content, provider-specific delivery

The portability commitment in ADR-0014 is about *content* — SKILL.md
bodies, AGENTS.md policy. Delivery is free to be provider-specific,
because delivery is not what other providers read.

A setup script placing provider-neutral `SKILL.md` files into a
container's skills directory is not a portability violation. The content
stays neutral; only the placement is Claude-aware; the repo stays empty.
Plugins are *one* delivery vehicle, not the definition of the content.

Corollary: never let a delivery mechanism's idiom leak into content. The
hardcoded `~/.claude/bin/...` paths in the broker skill are exactly this
failure — a delivery assumption written into portable text, which then
broke on a surface where the assumption did not hold.

### 5. Repo footprint proportional to what is genuinely project-specific

A repository should not have to carry a vendor's plumbing to be usable.
Every committed line of agent config is a line a human reviews, a line
that drifts, and a line that must be repeated across N repos.

When a mechanism requires per-repo files, that cost is justified only if
the thing being configured is genuinely per-repo.

### 6. Defer substance to a pinned, versioned single source

Where a provider surface must hold something, it holds **one line** that
defers to versioned content in this repo:

```bash
#!/bin/bash
curl -sSL https://raw.githubusercontent.com/pmgledhill102/agentic-coding-config/v1.3.0/cloud/bootstrap.sh | bash
```

Two properties make this work:

- **Pin to a tag or commit, never a branch.** A mutable ref means any
  compromise of this repo reaches every sandbox that starts afterwards.
- **The version bump is the release.** Cloud environments snapshot the
  setup script's result and re-run only when the script changes, so
  editing the pinned version is what rolls the change out — deliberate
  and visible, rather than content shifting underneath a cached image.

`curl | bash` is a supply-chain surface, accepted knowingly here: the
source is our own repo, pinned, over TLS, into an ephemeral
single-tenant container. It would not be acceptable on a durable host.

## Consequences

### Positive

- A repo becomes GCP-capable by *selecting an environment*, committing
  nothing. The N-repos tax disappears for the whole class.
- Vendor lock-in concentrates on a surface that is already vendor-owned
  and outside version control, keeping repos honestly multi-provider.
- The classification is reusable: the next capability (AWS, a private
  registry, a VPN) is placed by asking one question rather than
  re-arguing mechanisms.
- Environments become named capability profiles — `gcp-enabled`,
  `default` — which is a legible model for a human to reason about.
- Pinned bootstrap gives an explicit release channel, with cache
  invalidation as the deployment trigger rather than a nuisance.

### Negative / trade-offs

- **Environment config is invisible to the repo.** Nothing in a checkout
  says which environment a session ran in, so a failure that depends on
  environment state is harder to reproduce. Mitigation: the bootstrap
  script logs its pinned version at session start.
- **Environments proliferate.** Capability profiles multiply as
  combinations appear; there is no inheritance between them, so shared
  setup is copied. Watch for this before it becomes its own maintenance
  problem.
- **Two distribution paths persist.** Plugin for project configuration,
  bootstrap for environment capability. That is more machinery than
  picking one, and the boundary needs policing.
- **This narrows ADR-0014 point 3.** Project-scope plugin enablement
  remains correct for skills and policy, but is no longer the default
  answer for everything reaching a cloud session. ADR-0014 is amended,
  not superseded, and #48 should be re-read against this.
- **A cached environment can serve stale content** for up to its expiry
  if a version bump is forgotten. The pin makes this visible but does
  not prevent it.

### Questions this was held open for, now answered

Ratification waited on whether a `~/.claude` **created inside a
container** is read at all — the documentation says user-scope config
does not reach cloud sessions, but it means the developer's laptop does
not transfer, which is a different claim. Both halves are now settled by
running it:

- **Claude Code, 2026-08-13.** A sandbox session listed the skill from a
  container-created `~/.claude/skills` and invoked it **unprompted**, via
  the Skill tool, on finding `gcloud auth list` empty. Discovery works
  without being told the skill exists.
- **Codex, 2026-08-13.** The same bootstrap, unchanged, installed into
  `~/.agents/skills` and Codex listed `gcp-credentials` among its custom
  skills. The helper ran on `codex-universal` with no modification —
  POSIX `sh`, `curl` and `jq` are all present — and reached the broker
  through Codex's proxy.

Two vendors, one mechanism, nothing committed to the repo being worked
on. That is principle 1 demonstrated rather than asserted, and it is why
this ADR is Accepted rather than Proposed.

Codex needs configuration Claude does not, which belongs in the
environment and not here: agent-phase internet is **off by default** and
must be enabled, and the optional restriction to `GET`/`HEAD`/`OPTIONS`
blocks the broker outright, since `/request`, `/exchange` and `/revoke`
are all `POST`. Setup-script `export`s do not survive into the agent
phase either, so variables belong in the environment's own settings. All
of it is recorded in [`cloud/README.md`](../cloud/README.md).

### Still unverified

Whether Claude Code follows a **symlinked** skill directory. The Claude
result above was obtained with a real directory; the canonical layout now
places the file at `~/.agents/skills` with `~/.claude/skills` pointing at
it. If Claude stops listing the skill, that is why, and the fallback is a
real copy in both locations. This does not affect the principles: it is
an implementation detail of one delivery mechanism.

## Alternatives considered

**Commit plugin enablement to every repo (ADR-0014 point 3 applied
universally).** Rejected as the general answer for the reasons in
principles 3 and 5: vendor JSON in multi-provider repos, repeated N
times, for capabilities that are not per-repo. Retained for project
configuration, where per-repo declaration is the intent.

**Clone the whole of `home/` into the sandbox from the setup script.**
Rejected. It reintroduces the drift that per-repo copies already
demonstrated — a copied client diverged from upstream within a day
(#150, #152) — and it delivers project configuration through an
environment-scoped mechanism, which is principle 1 backwards.

**`CLAUDE_CODE_PLUGIN_SEED_DIR` to pre-populate the plugin cache.**
Kept as a fallback if marketplace fetching proves incompatible with the
network allowlist, not as the plan: seeding restores snapshot staleness
for content that should be fresh at session start.

**Do nothing; decide case by case.** Rejected — that is the current
state, and it has produced one re-derivation per surface, with the
`~/.claude/bin/` path assumption baked in along the way.

## References

- [ADR-0014](0014-portable-agent-config-architecture.md) — mechanisms this
  ADR classifies the use of
- [ADR-0015](0015-tiered-adrs.md) — tier conventions; this is a user-tier
  decision
- #48 — plugin distribution, to be re-read against principle 2
- #150, #152, #153, #154, #155 — findings from the 2026-08-12 sandbox run
  that motivated this
- gcp-org-management#269 — the validation exercise that surfaced it
