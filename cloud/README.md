# Cloud sandbox environments

Everything a vendor's cloud sandbox needs to gain this repo's capabilities,
without the repo you are working on carrying any of it.

`bootstrap.sh` is the whole mechanism: an environment's setup script fetches it
by ref and runs it, and it installs the helper and skill into the container.
See [ADR-0016](../adrs/0016-capability-delivery-principles.md) for why the
substance lives here rather than in the setup script itself.

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

## What lands where

| Path | What |
| ---- | ---- |
| `~/.agents/skills/gcp-credentials/SKILL.md` | the skill, canonical, vendor-neutral |
| `~/.claude/skills/gcp-credentials` | symlink to the above, for Claude Code |
| `/usr/local/bin/gcp-credentials` | the helper (or `~/.local/bin` unprivileged) |
| `~/.claude/bin/gcp-credentials` | symlink, because the skill still names that path |
| `/usr/local/bin/gcloud` | wrapper: prefers the broker token, renews it when stale |

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
