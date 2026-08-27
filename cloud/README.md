# Cloud sandbox environments

Everything a vendor's cloud sandbox needs to gain this repo's capabilities,
without the repo you are working on carrying any of it.

`bootstrap.sh` is the whole mechanism: an environment's setup script fetches it
by ref and runs it, and it installs the credential helper, a named set of
skills, and the composed agent policy into the container. See
[ADR-0016](../adrs/0016-capability-delivery-principles.md) for why the substance
lives here rather than in the setup script itself.

Which skills is an explicit whitelist — the `SKILLS` and `COMPOSED_SKILLS`
variables in the script — rather than everything under `home/skills/`. Raw
GitHub offers no directory listing, so a wildcard would need the API, a token
and a JSON parser; and the list being hand-maintained means adding a skill to
every sandbox is a decision someone makes rather than a side effect of creating
a file.

## Claude Code

Set these three things once per environment, at
[claude.ai/code](https://claude.ai/code) → the environment's settings.

### 1. Setup script

```bash
#!/bin/bash
# Rev: 1
curl -sSL https://raw.githubusercontent.com/pmgledhill102/agentic-coding-config/main/cloud/bootstrap.sh \
  | sh -s -- main --with-gcloud || true
exit 0
```

Drop `--with-gcloud` for an environment that does no Google Cloud work; it
saves a ~96 MB download and declares what kind of environment this is.

`--with-gh` installs the GitHub CLI from a pinned release — but **do not add
it to Anthropic-hosted environments**. Measured 2026-08-19: the egress proxy
authenticates `gh` for identity endpoints (`user`, `rate_limit`) yet 403s
every repo-scoped API path, and GraphQL serves only a pinned PR-review set —
so the session skills' gather sections come back `gh-unauthorized` rather
than populated (lane map on #257, cleanup on #273). The flag exists for
surfaces whose egress genuinely reaches the GitHub API, e.g. self-hosted
environments. On Anthropic-hosted sandboxes the GitHub MCP server remains the
only repo-data route, and the sandbox bodies of the session skills call it
directly rather than treating it as a fallback (#265).

**The `Rev:` comment is load-bearing.** The environment snapshots the setup
script's result and re-runs it only when the script text changes, the allowed
domains change, or roughly seven days pass. Because `main` never changes *as a
string*, pushing to `main` does not reach new sessions — they keep restoring the
snapshot built the first time. Bump the number to force a rebuild.

Pin a tag instead of `main` for anything beyond development:

```bash
  | sh -s -- v0.1.0 --with-gcloud || true
```

A mutable ref means any compromise of this repo reaches every sandbox that
starts afterwards. A tag also names, in the session's own log, which version it
is running.

`|| true` belongs to the caller, not the script: a non-zero exit fails the whole
session, while `bootstrap.sh` deliberately fails loudly so that a partial
install is visible rather than silent.

### 2. Allowed domains

Select **Custom**, tick *also include default list*, and add:

```text
credential-broker-<hash>-nw.a.run.app
dl.google.com
```

Obtain the broker hostname with `gcloud run services describe credential-broker`
against the project it is deployed to — named, with the region, in the
`sandbox-gcp-credentials` runbook in `gcp-org-management`. It is deliberately
not written here: this repo is public, and while the URL is not a credential,
publishing it hands a stranger the rate limit.

Both are needed because neither is on the Trusted default list, and each fails
in a way that reads as something else:

| Missing | Symptom | Actually |
| ------- | ------- | -------- |
| broker host | `could not resolve host` | the environment was never allowed to call it |
| `dl.google.com` | gcloud install fails | `cloud.google.com` and `gcloud.google.com` are on the default list and neither serves the tarball |

`raw.githubusercontent.com` is already on the default list, so fetching the
bootstrap itself needs nothing added.

### 3. Environment variables

| Variable | Value |
| -------- | ----- |
| `CREDENTIAL_BROKER_URL` | the broker hostname above, with scheme |
| `CREDENTIAL_BROKER_REQUEST_KEY` | the **`cloud`** key, from the password manager |

Use the `cloud` key, not the `local` one. The approval card names which key was
used, and "key cloud while I am at my laptop" is information worth keeping
truthful.

Cloud environments have **no secrets store** — anyone who can use the
environment can read its variables, and the documentation says not to put
credentials there. The request key is a deliberate exception: it only gates
*opening* a request, the human approval is the real control, and rotation is
documented. Treat that as a knowing decision rather than a default.

## Codex

**Not yet established.** The mechanism should port — cloud sessions on both
Claude and Codex ignore user-level config from your machine and both run an
environment setup script, and `bootstrap.sh` writes its canonical skill to
`~/.agents/skills`, which Codex scans natively.

What a first run needs to answer:

1. Does the sandbox run a setup script, and in what shell?
2. Can it reach `raw.githubusercontent.com`, or is there an allowlist to extend?
3. Is the skill discovered from `~/.agents/skills`?
4. Does the helper work unchanged? It is POSIX `sh` plus `curl` and `jq`, with
   nothing Claude-specific in it.

Fill this section in from that run rather than from the documentation.

## Local machines

Not this. `~/.claude` is chezmoi-managed from `home/`; the bootstrap is for
containers that start empty.

## Ending access, and incident response

Revocation levels and what to do about a possibly-exposed token or request key:
[`docs/runbooks/sandbox-gcp-credentials.md`](../docs/runbooks/sandbox-gcp-credentials.md).

## What lands where

| Path | What |
| ---- | ---- |
| `~/.agents/skills/gcp-credentials/SKILL.md` | the skill, canonical, vendor-neutral |
| `~/.claude/skills/gcp-credentials` | symlink to the above, for Claude Code |
| `/usr/local/bin/gcp-credentials` | the helper (or `~/.local/bin` unprivileged) |
| `~/.claude/bin/gcp-credentials` | symlink, because the skill still names that path |
| `/usr/local/bin/gcloud` | wrapper: prefers the broker token, renews it when stale |
| `~/.agents/skills/<name>/SKILL.md` | each whitelisted skill, canonical — the sandbox body for a composed one |
| `~/.claude/skills/<name>` | symlink to the above, for Claude Code |
| `~/.agents/AGENTS.md` | the composed policy profile |
| `~/.claude/CLAUDE.md` | the Claude adapter profile (Claude profiles only) |
| `~/.claude/bin/<script>` | the four session helper scripts |
| `~/.agents/.bootstrap-manifest` | what this run installed: ref, SHA, profile, skills, helpers |
| `~/.config/git/hooks/pre-commit` | global git hook, with `--with-precommit` |
| `~/.claude/settings.json` | harness hook wiring, with `--with-hooks` (merged, not replaced) |
| `~/.claude/bin/*-claude-hook` | the three harness hook scripts, with `--with-hooks` |
| `/usr/local/bin/pre-commit`, `/usr/bin/shellcheck`, `/usr/local/bin/actionlint` | with `--with-precommit` |
| `/usr/local/bin/gh` | the GitHub CLI, pinned release, with `--with-gh` |

Whitelisted today: `promote-journal-inbox`, `retrospective`, `start-session`,
`end-session`. The 15 `setup-*` skills are held back pending a currency review
— they are repo-scaffolding procedures a sandbox session rarely needs, and they
predate this surface.

The script keeps two lists, because there are two sources:

- **`COMPOSED_SKILLS`** — the three session skills (#265, #288). Each has a
  workstation body and a cloud-sandbox body built from one shared fragment set,
  so its artefact lives at `profiles/<profile>/skills/<name>/SKILL.md` and is
  fetched by profile, exactly as `AGENTS.md` and `CLAUDE.md` are.
- **`SKILLS`** — one body for every surface, fetched from `home/skills/`.
  `promote-journal-inbox` is the only entry (#289): its pre-flight tests the
  repo rather than a path, and it already prefers MCP with `gh` as the
  fallback, so nothing about it differs by surface. That is ADR-0018 principle
  8 working as intended — one body is the default, and a per-surface pair has
  to earn itself.

Moving a skill between the lists is part of adding or removing its manifest
entry; get it backwards and the fetch 404s at install, naming the skill.

The session skills shell out to four helper scripts, delivered alongside them
into `~/.claude/bin/`. They are not optional: the skills invoke them by name, so
a missing helper fails at the point of use rather than at install.
`start-session-claude-drift` is among them because
`start-session-gather-state` runs it as a sibling — a dependency nothing in the
skill text mentions.

**`gh` does not answer repo questions in these containers**, whether it is
absent or installed-and-403ed (#273, #276), so the gather scripts' GitHub
sections always come back `gh-unavailable` or `gh-unauthorized`. That is no
longer something a session has to notice and route around: the sandbox bodies
of both session skills issue the MCP queries as ordinary steps and never
mention `gh` at all. What those queries cannot express — a `-is:blocked` filter
on issues, an author filter on PRs — the sandbox text states outright rather
than implying a filter that was not applied.

## Pre-commit enforcement

Sandboxes bypassed the pre-commit framework entirely until `--with-precommit`:
the binary was absent and no `.git/hooks/pre-commit` existed, so a repo's
committed `.pre-commit-config.yaml` did nothing here (#254).

```sh
  | sh -s -- <REF> --with-precommit
```

It installs `pre-commit`, plus `shellcheck` and `actionlint`, which this
estate's config runs as `language: system` hooks — they use the binary on
`PATH` so the hook and CI cannot drift to different versions, which only works
if the binaries are present. Installing them is the point; the config's `SKIP=`
escape is for a laptop missing one, and normalising it would leave enforcement
that is routinely skipped.

Opt-in for two reasons: it is the only part of this script needing the Ubuntu
archives, so an environment that cannot reach them keeps working by not asking;
and the one line an environment carries should declare what kind of environment
it is.

**The hook is global, via `core.hooksPath`, not `pre-commit install` per repo.**
This script runs from an environment setup script whose ordering against the
session's clone it cannot rely on — the repository may not exist yet, and may
not be the only one. A global hook is set once and applies however and whenever
a repo arrives. The trade-off is real and worth knowing: `core.hooksPath`
*replaces* a repo's own `.git/hooks` rather than adding to it, and
`pre-commit install` will warn that it is being overridden. In this estate
hooks come from pre-commit anyway.

The hook exits 0 in a repo with no `.pre-commit-config.yaml`. Such a repo is
not opting out of anything — it has no configuration to run, and blocking its
commits would be the container inventing policy the repo never asked for.

This is the vendor-neutral half of enforcement: git runs `.git/hooks` itself,
so it needs no agent configuration and covers Claude, Codex and a human typing
`git commit` identically. The harness-hook half — `home/hooks/hooks.json`,
which feeds failures back into the agent's context — is tracked separately
in #254, and is blocked on whether a container-created
`~/.claude/settings.json` registers hooks at all.

## Harness hooks

`--with-precommit` gives you a native git hook, which blocks a bad commit.
`--with-hooks` adds the harness layer, which runs inside the agent loop and
returns the failure into its context — so the agent reads the message and fixes
the cause rather than simply being stopped. Both are worth having; neither
replaces the other.

```sh
  | sh -s -- <REF> --with-precommit --with-hooks
```

Viable because a container-created `~/.claude/settings.json` **is** honoured —
measured 2026-08-18 by planting one and watching a `PreToolUse` hook fire eight
seconds later, with no session restart. That is the third
documented-as-unavailable user-scope path to work from inside a container, after
`~/.claude/skills/` and `~/.claude/CLAUDE.md`.

The wiring is taken from `home/settings.json` rather than restated in the
script. That file is the workstation's, and it already invokes
`~/.claude/bin/<hook>` directly — the same paths the bootstrap installs to — so
both surfaces run identical hooks from one source instead of a copy that drifts.
A dispatcher used to sit in front of the three script hooks, standing down when
a `~/.claude/bin` copy was present so a plugin-enabled workstation would not run
each hook twice; it was withdrawn with the plugin channel (#312), and each
script is now named directly.

**Merged, not overwritten.** A container may already have a `settings.json`, and
replacing it wholesale would silently drop whatever else it holds. Note
`~/.claude/launcher-settings.json` is a different file with its own hooks,
written by the harness; nothing here touches it, and both are read.

Two of the three degrade to no-ops in a sandbox rather than failing:
`prepush-guard-claude-hook` needs `gh`, which is absent (#257), and
`precommit-claude-hook` needs the pre-commit framework, so it does nothing
without `--with-precommit`.

## Knowing whether a container is stale

The environment re-runs its setup script only when the script text changes, the
allowed hosts change, or roughly seven days pass — so a push does not reach new
sessions and a sandbox can be running week-old content with nothing saying so.
The credential helper solved its half server-side, by sending a version the
broker can refuse (#182); skills, policy and helper scripts have no server on
the other end.

So the bootstrap writes `~/.agents/.bootstrap-manifest` recording the ref, the
resolved SHA, the timestamp, the profile, and what it installed. `start-session`
reads it in its `bootstrap_currency` section and reports `current`, `behind`,
`pinned`, `no-manifest` or `unknown`. On `behind` it gives the remedy, which is
re-running the bootstrap — immediate, no restart.

`git ls-remote` resolves the ref rather than the GitHub API: no token, no JSON
parsing, and git is already required to be here.

**What this guarantees, precisely.** Not that every session starts fresh. The
check ships inside the thing it checks, so a container older than the check
cannot report it — that self-heals after one cache cycle rather than
immediately. And it runs only when `start-session` runs. It is advisory. The
automatic version would be a `SessionStart` hook, which is blocked on whether
hooks in a container-created `~/.claude/settings.json` are honoured at all
(#254).

## Which profile

`--profile <name>` selects the composed context profile, defaulting to
`claude-cloud-sandbox`. A Codex environment passes `--profile
codex-cloud-sandbox`:

```sh
curl -sSL https://raw.githubusercontent.com/pmgledhill102/agentic-coding-config/<REF>/cloud/bootstrap.sh \
  | sh -s -- <REF> --profile codex-cloud-sandbox
```

The environment declares which harness it is rather than the script sniffing
for one. Per ADR-0018 principle 1 surface differences are resolved at delivery,
and the caller is the only party that knows the answer without guessing.

Profiles are built and verified in CI by `tests/compose-context.py`, which also
refuses to compose a sandbox profile that includes a workstation fragment. That
is what stops "run `chezmoi apply`" reaching a container with no chezmoi, so
this script does not have to check.

Claude profiles ship two files, because Claude Code reads `CLAUDE.md` and not
`AGENTS.md`. Codex profiles ship `AGENTS.md` only, and it lands in
`~/.agents/`. **Where Codex actually reads user-level `AGENTS.md` is not yet
established (#176)** — `~/.agents/` is the vendor-neutral location its skills
are already read from, not a verified instruction path.

## Updating a running session

Re-run the bootstrap directly; no environment edit, no restart:

```sh
curl -sSL https://raw.githubusercontent.com/pmgledhill102/agentic-coding-config/main/cloud/bootstrap.sh \
  | sh -s -- main --with-gcloud
```

Keep `--with-gcloud` even where gcloud exists: it skips the download but is also
the branch that installs the gcloud wrapper.

Skills are read when the agent starts, so a newly installed skill appears after
the session restarts or resumes. The helper is usable immediately.

## When the broker says the helper is too old (exit 8)

The helper sends a `X-Client-Version` header on `/request` and `/poll`, and the
broker refuses anything below its minimum with HTTP 426 — **before** posting an
approval card, so a stale client never spends a human approval it cannot
complete. The helper exits 8 and renders the broker's hint.

This exists because a client too old to understand a new broker state is also
too old to know that the state exists: three broker releases in a row
(`warming`, `failed`, `provisioning`) each broke running sessions with
`unexpected state: <name>`. Self-checking asks the stale component to detect its
own staleness, which only works for cases it already anticipated. The broker
always knows what it needs, so the check belongs there.

**Why this bites cloud sessions specifically.** The environment snapshots the
setup script's result and re-runs it only when the script *text* changes, the
allowed domains change, or roughly seven days pass. Because `main` never changes
as a string, **pushing to `main` does not reach new sessions** — they keep
restoring a snapshot built with whatever helper was current then. A cloud
session can be running a week-old client with nothing to indicate it.

Two remedies, in the order you want them:

| Situation | Do this |
| --- | --- |
| The session in front of you | Re-run the bootstrap (above). Takes effect immediately for the helper |
| Every session from now on | Bump `Rev:` in the setup script, forcing a rebuild |

Do both. The re-run unblocks the task at hand; the `Rev:` bump is what stops the
next session hitting the same wall. On a local machine the equivalent is
`chezmoi apply --refresh-externals` — see the skill doc.

**The version constant is bumped in the same commit as the wire change that
needs it**, on both sides. That is the whole value of the mechanism: the bump is
the moment someone notices a client change is required, rather than a session
discovering it mid-task. The helper's `CLIENT_VERSION` carries a comment saying
so; the broker's `clientversion.go` keeps the authoritative history.

Do **not** make the skill fetch and install a newer helper before running. The
helper is what displays the verification phrase, which makes it the one
client-side component that is security-relevant — a compromised helper could
show a phrase that does not match the request it made and walk a human into
approving something else. Updating that component *inside* the credential flow
means the code implementing the phrase check can change during the request it is
checking. Detect and instruct; do not self-modify.
