# Cloud sandbox environments

Everything a vendor's cloud sandbox needs to gain this repo's capabilities,
without the repo you are working on carrying any of it.

`bootstrap.sh` is the whole mechanism: an environment's setup script fetches it
by ref and runs it, and it installs the credential helper, a named set of
skills, and the composed agent policy into the container. See
[ADR-0016](../adrs/0016-capability-delivery-principles.md) for why the substance
lives here rather than in the setup script itself.

**This file is the operator manual — what to set, what each flag does, how to
recover.** For what the layers are, what runs when, what it all costs and how
the surfaces differ, see
[`docs/cloud-sandbox-design.md`](../docs/cloud-sandbox-design.md).

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

```sh
PROFILE=claude-cloud-sandbox
REF=main
# Rev: 1

curl -sSL --retry 3 --retry-delay 2 \
  "https://raw.githubusercontent.com/pmgledhill102/agentic-coding-config/$REF/cloud/bootstrap.sh" \
  -o /tmp/bootstrap.sh || echo "[setup] could not fetch bootstrap.sh"

{ sh /tmp/bootstrap.sh "$REF" --profile "$PROFILE"; echo $? > /tmp/bootstrap.rc; } 2>&1 \
  | tee /tmp/bootstrap.log

echo "[setup] bootstrap exit=$(cat /tmp/bootstrap.rc 2>/dev/null) at $(date -u +%FT%TZ)"
exit 0
```

**The first three lines are the whole per-environment configuration.** Below
them the script is byte-identical on every surface, which is the point: a
Codex environment differs from a Claude one by one word, and a pinned
environment from a tracking one by one word, in a place obvious enough that
nobody has to read the rest to find it.

`REF` is a variable rather than typed twice because it appears in two places —
the ref this script is fetched from, and the ref it installs everything else
from. Those straddling different versions is precisely the failure the pin
exists to prevent, and two literals are two chances to update only one.

**Do not put a shebang in this field.** The harness writes the field's contents
into a generated `/tmp/init-script-*.sh` beneath a header of its own and runs
that, so a `#!/bin/bash` you paste is never line 1 and never takes effect. Intact
it is a comment; lose the `#` in transit and it becomes a command, which is how a
live environment produced this:

```text
Setup script failed with exit code 127.
/tmp/init-script-2496021182.sh: line 3: !/bin/bash: No such file or directory
```

Line 3 is the field's line 1. Nothing had run yet — not `curl`, not the
bootstrap — and the session was already over. Omitting the line removes the whole
class of failure, and costs nothing, because the harness supplies the interpreter.

For the same reason, keep the field POSIX. Which shell the harness uses is its
choice, not yours, so a bashism only works by luck — the form above avoids
`PIPESTATUS` by parking the exit status in a file, which is why the bootstrap
runs inside `{ … }` rather than being piped directly into `tee`.

Downloading the bootstrap to a file rather than piping it into `sh` is also
deliberate: it separates "could not fetch" from "ran and failed", and it keeps
the run's own exit status reachable.

### What a profile includes

The profile selects the capabilities as well as the context, so most
environments need no capability flags at all:

| Profile | gcloud | pre-commit | hooks | gh |
| --- | --- | --- | --- | --- |
| `claude-cloud-sandbox` | yes | yes | yes | no |
| `codex-cloud-sandbox` | yes | yes | no | no |
| `*-workstation` | no | no | no | no |

These are read off the profile name rather than held in a table the script
would have to grow a row in per profile. A `claude-*` profile gets the harness
hooks because `~/.claude/settings.json` is a Claude mechanism and Codex does not
read it — ADR-0016 principle 3, provider-specific coupling on provider-specific
surfaces, applied to the installer. Anything `*-cloud-sandbox` gets pre-commit
and gcloud, because a sandbox is disposable and rebuilt from a script: the
argument for making a developer opt into enforcement is about protecting
somebody's laptop, and there is no laptop here. #254 is what its absence cost.

`gh` is off everywhere. It is documented below as counterproductive on
Anthropic-hosted sandboxes, so it waits for a caller who knows their egress.

### Overriding a profile

Every capability takes `--with-X` to force it on and `--no-X` to force it off.
Either beats the profile wherever it sits on the line, so ordering against
`--profile` does not matter:

```sh
sh /tmp/bootstrap.sh "$REF" --profile "$PROFILE" --no-gcloud
```

`--no-gcloud` is the one worth knowing: it saves a ~96 MB download in an
environment that does no Google Cloud work. `--no-precommit` is the escape for
an environment that cannot reach the Ubuntu archives, since that is the only
part of the script needing them.

The run reports what it resolved, because with defaults in play the command
line no longer says what happened:

```text
[bootstrap] profile -> claude-cloud-sandbox
[bootstrap] caps    :  gcloud=yes precommit=yes hooks=yes gh=no terraform=yes
```

The same set is written to `~/.agents/.bootstrap-manifest`, which is where to
look when a container is behaving as though something is missing.

`--with-terraform` installs `terraform`, `tflint` and `checkov`, and seeds
the tflint google ruleset that `tflint --init` cannot fetch here, so a repo
whose `.pre-commit-config.yaml` calls the Terraform hooks can actually run
them. **On by default for a sandbox**, like `--with-precommit` and for the
same reason: a disposable container rebuilt from a script has no developer
setup to protect, so a gate that is present beats a download that is avoided.
`--no-terraform` is the refund for an environment that does no Terraform work.
It installs inside `--with-precommit`, since serving that config is the whole
reason the binaries are here: `--with-terraform --no-precommit` installs
nothing.

This buys **coverage**, not the ability to push. A container without these
tools pushes fine: `precommit-claude-hook` classifies a hook that fails purely
because its binary is missing as *not checked* and lets the command through,
naming what went unchecked (#335). Before that fix, every push in such a
container needed `--no-verify` — five out of five in one session, which is how
a guard stops being a guard.

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

```sh
REF=v0.1.0
```

One word, one place — which is why `REF` is a variable rather than the two
literals it replaced.

A mutable ref means any compromise of this repo reaches every sandbox that
starts afterwards. A tag also names, in the session's own log, which version it
is running.

The trailing `exit 0` belongs to the caller, not the script: a non-zero exit
fails the whole session, while `bootstrap.sh` deliberately fails loudly so that
a partial install is visible rather than silent. Swallowing the status is a
choice the environment makes, which is why the snippet still records the real
one in its `[setup] bootstrap exit=` line and keeps `/tmp/bootstrap.log` — a
session that came up half-installed can be diagnosed from inside itself.

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

Set the same three things once per environment, in the Codex environment's
settings. This section states what a run on 2026-08-13 established, not what
the documentation implies.

### 1. Setup script

```sh
PROFILE=codex-cloud-sandbox
REF=main
# Rev: 1

curl -sSL --retry 3 --retry-delay 2 \
  "https://raw.githubusercontent.com/pmgledhill102/agentic-coding-config/$REF/cloud/bootstrap.sh" \
  -o /tmp/bootstrap.sh || echo "[setup] could not fetch bootstrap.sh"

{ sh /tmp/bootstrap.sh "$REF" --profile "$PROFILE"; echo $? > /tmp/bootstrap.rc; } 2>&1 \
  | tee /tmp/bootstrap.log

echo "[setup] bootstrap exit=$(cat /tmp/bootstrap.rc 2>/dev/null) at $(date -u +%FT%TZ)"
exit 0
```

**One word differs from the Claude block above — the profile.** Everything
said there about `REF`, the absent shebang, keeping the field POSIX, the
`Rev:` comment and the trailing `exit 0` applies here unchanged, and the
profile table under *What a profile includes* says what `codex-cloud-sandbox`
turns on: gcloud and pre-commit yes, harness hooks no.

The setup phase has network access and reached `raw.githubusercontent.com` to
fetch the bootstrap with nothing added to the allowlist. The helper runs
unchanged on `codex-universal` — POSIX `sh`, `curl` and `jq` are all present,
and nothing in it is Claude-specific. The skill is discovered from
`~/.agents/skills`, which Codex scans natively: it listed `gcp-credentials`
among its custom skills and invoked it **unprompted** from a prompt that never
mentioned credentials. The two-step phrase flow works end to end, including
refusing to run the target script when the mint failed.

### 2. Allowed domains

The same two entries as the Claude section — the broker host and
`dl.google.com` — obtained the same way, and for the same reasons.

**Two Codex-specific network settings matter more than the list does, because
neither fails in a way that points at itself:**

- **Agent-phase internet is off by default and must be enabled.** The entire
  broker flow — request, wait, renew — happens in the *agent* phase, not in
  setup. With it off the bootstrap installs cleanly during setup and then
  nothing works, which reads as a broken helper rather than as a network
  policy.
- **The optional restriction to `GET`/`HEAD`/`OPTIONS` blocks the broker
  outright.** Its endpoints are all `POST`, so an environment with the network
  on and the host allowlisted still fails every request while that filter is
  set — and the failure arrives as an HTTP status from a host that plainly
  resolved.

*An observation, not a guarantee:* the run reached the broker through Codex's
proxy with no `HTTP_PROXY`/`HTTPS_PROXY` tuning and no custom CA certificates.
The documentation does not say whether either is set, and at least one
third-party write-up reports `curl` needing proxy-aware configuration, so
treat this as what one run saw rather than as something the surface promises.

### 3. Environment variables

The same two variables as the Claude section, with the same values and the
same reason to use the **`cloud`** key rather than the `local` one. The
no-secrets-store caveat there applies here too.

**Set them in the environment's own settings, not from the setup script.**
Codex runs setup in a separate Bash session, so an `export` there does not
survive into the agent phase — which is the only phase where the helper runs.
The symptom is a helper that reports missing configuration at the moment of
use, having installed without complaint.

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
| `~/.claude/bin/<script>` | the five session helper scripts |
| `~/.agents/.bootstrap-manifest` | what this run installed: ref, SHA, profile, skills, helpers |
| `~/.config/git/hooks/pre-commit` | global git hook, with `--with-precommit` |
| `~/.cache/pre-commit/` | the warmed hook environments, with `--with-precommit` (~222 MB) |
| `~/.claude/settings.json` | harness hook wiring, with `--with-hooks` (merged, not replaced) |
| `~/.claude/bin/*-claude-hook` | the three harness hook scripts, with `--with-hooks` |
| `/usr/local/bin/pre-commit`, `/usr/bin/shellcheck`, `/usr/local/bin/actionlint`, `markdownlint-cli2` (npm global), `cspell` (npm global), `semgrep` (uv tool) | with `--with-precommit` |
| `/usr/local/bin/gh` | the GitHub CLI, pinned release, with `--with-gh` |
| `/usr/local/bin/terraform`, `/usr/local/bin/tflint`, `checkov` | the Terraform toolchain, with `--with-terraform` |
| `~/.tflint.d/plugins/…/tflint-ruleset-google/` | the tflint google ruleset, seeded because `tflint --init` is 403ed here, with `--with-terraform` |

Whitelisted today: `promote-journal-inbox`, `retrospective`, `start-session`,
`end-session`. The other **16** skills under `home/skills/` are held back
pending the currency review on
[#247](https://github.com/pmgledhill102/agentic-coding-config/issues/247):

- the **15 `setup-*` skills** — repo-scaffolding procedures a sandbox session
  rarely needs, and they predate this surface;
- **`repo-review`**, added to that hold on 2026-08-28. It was absent without
  ever having been decided about — the arithmetic never closed, and #239 found
  it as the unaccounted sixteenth. Folding it in rather than whitelisting it
  keeps one decision in one place, but note what the hold costs while it
  stands: `README.md` calls the skill portable, and ADR-0015 names it as the
  audit for whether an ADR still fits its tier, so a decision recorded from a
  sandbox cannot be currency-checked from one.

That list being 16 rather than 15 is the only thing the hold is claiming. It is
not a claim that any of the 16 is unwanted here — #247 is where that is decided.

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

On by default for every `*-cloud-sandbox` profile; `--no-precommit` opts out.

It installs `pre-commit`, plus `shellcheck` and `actionlint`, which this
estate's config runs as `language: system` hooks — they use the binary on
`PATH` so the hook and CI cannot drift to different versions, which only works
if the binaries are present. Installing them is the point; the config's `SKIP=`
escape is for a laptop missing one, and normalising it would leave enforcement
that is routinely skipped.

It also installs `markdownlint-cli2` from npm, pinned to the rev
`.pre-commit-config.yaml` declares — bump the two together. That one is *not* a
`language: system` hook: the pre-commit hook builds its own node environment
and CI uses the action, so this install is what makes `markdownlint-cli2
"**/*.md"` — the gate this repo documents first — runnable, since that needs
the binary on `PATH`.

It used to be opt-in for two reasons: it is the only part of this script needing
the Ubuntu archives, so an environment that cannot reach them keeps working by
not asking; and the one line an environment carries should declare what kind of
environment it is.

The second reason is now served better by `--profile`, which declares the same
thing at less cost. The first survives as `--no-precommit`, but it is an escape
rather than a default: an enforcement mechanism that arrives only when someone
remembers to ask for it is the state #254 described, and the whole point of a
sandbox being rebuilt from a script is that nobody has to remember.

**It also warms the hook cache, so the first commit does not pay for it.**
`pre-commit` builds a hook's environment on first use, and in this estate that
first use is a *commit* — inside `precommit-claude-hook`'s 120-second timeout.
Cold, the estate's hook set is about two minutes, because `gitleaks`,
`actionlint` and `shfmt` are `language: golang` hooks compiled from source. Both
outcomes of that race are wrong: a hook that times out and lets the commit
through is a gate that silently did not run, and a commit killed for a reason
unrelated to its content is a failure that succeeds on retry (#441).

What makes warming work is *which filesystem*: the setup script's is
snapshotted and reused for about seven days, the session's is not — so a cache
built in-session is rebuilt in every container, and one built here is free at
every session start. It runs as its own capability, `precommit-warm`, and
`degraded=` therefore distinguishes "no gate" from "a gate with a slow first
commit".

Two mechanisms, for the reason the global hook exists at all — at setup-script
time the repository may not exist yet, and may not be the only one:

1. [`cloud/precommit-warm.yaml`](precommit-warm.yaml), the estate's standard
   hook set with pinned revs. pre-commit keys its cache on `(repo URL, rev)`, so
   warming those pins warms every repo pinned to the same ones, clone or no
   clone. This is the guarantee.
2. Every `.pre-commit-config.yaml` found in the workspace, up to five, for the
   revs the pinned file does not carry.

A repo on a different rev gets a **partial** warm, never a failure: the hooks it
shares are cached and the rest build on first use. Keeping that rare is #442.
The measured cost is in
[`docs/cloud-sandbox-design.md`](../docs/cloud-sandbox-design.md) §3.

One dependency worth knowing about: the golang hooks need `go` on `PATH`. The
sandbox image ships it at `/usr/local/go/bin`, and when it is absent pre-commit
fetches its own toolchain from `https://go.dev/dl/?mode=json` — which this
egress proxy answers 403. The warm logs a warning and degrades rather than
hanging; the remedy is allowlisting `go.dev` or putting Go back.

**The hook is global, via `core.hooksPath`, not `pre-commit install` per repo.**
This script runs from an environment setup script whose ordering against the
session's clone it cannot rely on — the repository may not exist yet, and may
not be the only one. A global hook is set once and applies however and whenever
a repo arrives. The trade-off is real and worth knowing: `core.hooksPath`
*replaces* a repo's own `.git/hooks` rather than adding to it. In this estate
hooks come from pre-commit anyway.

**`pre-commit install` does not warn under `core.hooksPath` — it refuses, and
exits 1.** Measured 2026-09-15:

```text
$ git config core.hooksPath /root/.config/git/hooks
$ pre-commit install
[ERROR] Cowardly refusing to install hooks with `core.hooksPath` set.
hint: `git config --unset-all core.hooksPath`
$ echo $?
1
```

This is the thing to write a repo-side hook against, because the failure lands
in exactly the containers the bootstrap got *right*: a `SessionStart` hook that
runs `pre-commit install` under `set -e` fails session start wherever the global
hook is correctly installed. Anything belt-and-bracing the gate from inside a
repo has to call `install` only when `core.hooksPath` is unset.

**`pre-commit install-hooks` is unaffected** — exit 0, builds the environments,
writes no hook — which is why the two have to be called separately, and why the
warm above uses it. A repo that genuinely needed bespoke per-repo hooks would
want the other mechanism, and would have to unset `core.hooksPath` to get it.

The hook exits 0 in a repo with no `.pre-commit-config.yaml`. Such a repo is
not opting out of anything — it has no configuration to run, and blocking its
commits would be the container inventing policy the repo never asked for.

This is the vendor-neutral half of enforcement: git runs `.git/hooks` itself,
so it needs no agent configuration and covers Claude, Codex and a human typing
`git commit` identically. The harness-hook half — the one that feeds failures
back into the agent's context — is delivered by `--with-hooks`, and the next
section covers how. It was once blocked on whether a container-created
`~/.claude/settings.json` registers hooks at all (#254); it does, measured, and
the declaration it merges is `home/settings.json`. The `home/hooks/hooks.json`
this paragraph used to name was the plugin copy, withdrawn with the plugin
in #312.

## Harness hooks

`--with-precommit` gives you a native git hook, which blocks a bad commit.
`--with-hooks` adds the harness layer, which runs inside the agent loop and
returns the failure into its context — so the agent reads the message and fixes
the cause rather than simply being stopped. Both are worth having; neither
replaces the other.

Both are on by default for `claude-*` sandbox profiles. A Codex profile gets
pre-commit but not the harness hooks, because Codex does not read
`~/.claude/settings.json`.

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
PROFILE=codex-cloud-sandbox
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
  -o /tmp/bootstrap.sh
sh /tmp/bootstrap.sh main --profile claude-cloud-sandbox
```

Do not add `--no-gcloud` here even where gcloud already exists: the install is
skipped anyway when it is on `PATH`, and that same branch is what installs the
gcloud wrapper.

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
