# Runbook: sandbox GCP credentials

Operating the credential broker from the **client side** — the half that lives
in this repo, plus the procedures for ending access when something looks wrong.

Design and trust model: ADR 021 (broker) and ADR 022 (sandbox provisioning), in
`pmgledhill102/gcp-org-management`.

## Scope, and what is deliberately elsewhere

This repo is public. Anything naming a project, a hostname, or an identity in
the estate lives in the private `sandbox-gcp-credentials` runbook in
`gcp-org-management`, and is **linked, not copied** — a copy drifts, and this
one would drift into a public repo.

| Concern | Where |
| --- | --- |
| Deploying the broker; onboarding a project; Terraform for the agent SAs | Private runbook, `gcp-org-management` |
| Broker hostname, project IDs, region | Private runbook |
| Per-environment setup: setup script, allowed domains, environment variables | [`cloud/README.md`](../../cloud/README.md) |
| Using it in a session: request, phrase, wait, renew, release | [`home/commands/gcp-credentials.md`](../../home/commands/gcp-credentials.md) |
| The client itself | [`home/bin/gcp-credentials`](../../home/bin/gcp-credentials) |
| Ending access; incident response | **This file** |

## The model in one paragraph

One human approval creates a **grant** of 1–7 days. Inside that window the
helper silently re-mints **1-hour** GCP access tokens with no further approvals.
The token is written straight from the HTTP response to a 0600 file and never
passes through a shell variable, so it never reaches the transcript or the
model's context. What a stolen token buys is therefore one project, a limited
role set, and at most an hour — the broker's job is to make token theft boring.

## Ending access

Three levels. Pick by what you are actually worried about, because they differ
in blast radius and in how fast they take effect.

**All three end *access*. None of them deletes the project, and none should.**
The broker resolves a repo to its sandbox project and creates one only when the
repo has none, so the project belongs to the repo rather than to whichever session
was first to ask: later sessions on the same repo resolve to it, and others may
hold live grants on it right now. A sandbox is also created with a fixed TTL and a
budget cap — today 7 days and £25/mo, printed on the approval card — and a
scheduled job deletes it when the TTL lapses (gcp-org-management ADR 008, ADR 022).
A grant is clamped to that expiry, which is why one can come back shorter than
asked for. So an unattended sandbox is not a leak accumulating cost, and
`gcp-credentials created` is a record of what this session brought into being, not
a teardown list. Retiring one early is a deliberate act taken knowing what else
depends on it; extending one is `/sandbox extend`, capped at 30 days.

### 1. `release` — this machine stops using the credentials

```sh
~/.claude/bin/gcp-credentials release
```

Stops the refresh loop, removes the local token, restores the gcloud
configuration that was active before. **The grant stays live at the broker**, so
`renew` would bring it straight back.

Use at the end of a session on a shared or local machine. Not an incident
response.

### 2. `revoke` — the grant ends

```sh
~/.claude/bin/gcp-credentials revoke
```

Deletes the grant at the broker, so no further tokens can be minted, then does
everything `release` does. **Residual exposure: up to one hour** — an
already-minted token stays valid until it expires. There is no un-minting.

Use when access should end outright: work finished early, or anything about the
session looks off.

If the broker is unreachable, `revoke` cleans up locally and says so — the grant
may still be live. Retry, or escalate to level 3.

### 3. Disable the service account — everything stops now

The hard kill, for when a live token is believed to be in the wrong hands and an
hour is too long to wait:

```sh
gcloud iam service-accounts disable agent-sandbox@<project>.iam.gserviceaccount.com
```

This invalidates tokens already issued, which levels 1 and 2 cannot. It needs
admin credentials — that is, **not** an agent session's credentials, by design.
Re-enable with `enable` once the grant is revoked and the incident is closed.

## Incident response

### A token may have been exposed

Most likely cause: something printed or copied the token file — a `cat`, a
debug dump, a tool that echoes its environment. The skill forbids reading that
file for exactly this reason.

1. **`revoke`** (level 2). Do this first; it costs nothing and stops the bleeding.
2. If the exposure reached anywhere durable — a transcript, a log, a pasted
   snippet, a CI job's output — **disable the service account** (level 3) rather
   than waiting out the hour.
3. Check what the identity could reach: the agent SA holds a limited role set on
   **one** project. Confirm which from the grant, then review that project's
   audit log for the exposure window. Agent activity is attributable, because
   every call from a session carries the per-project SA rather than the human's
   identity — that separation is what makes this step possible at all.
4. Request fresh credentials normally afterwards. A new grant is a new approval
   and a new phrase; nothing carries over.

### The request key may have leaked

The request key only gates *opening* a request. It cannot approve one — the
human approval is the real control, and a stranger with the key gets a card the
owner did not expect and should deny.

Still worth rotating, because the key is what stops approval spam:

1. Rotate the key at the broker (private runbook).
2. Update it everywhere it is configured: `CREDENTIAL_BROKER_REQUEST_KEY` in each
   cloud environment, and `~/.config/claude/credential-broker/request-key` (mode
   0600) on each machine.
3. Cloud environments have no secrets store, so the key sits in environment
   variables readable by anyone who can use the environment. That is a knowing
   exception, documented in `cloud/README.md` — rotation is the compensating
   control, so actually do it.

### An approval card arrived that nobody expected

**Deny it.** A card with no session running is grounds to deny, always — this is
the case the whole phrase mechanism exists for.

The phrase is generated by the broker and returned only to the requesting
session, so a card whose phrase does not match what is on your screen is not
your session's card. Approving it would hand credentials to whoever made the
request.

After denying: the card names which request key was used, which tells you
whether to rotate (above). A deny costs nothing and a wrong approval costs a
project, so the asymmetry is not close.

### A session is behaving oddly while holding a grant

Sessions on one repo share a project and an identity at `roles/owner`, so a
second live grant means someone else's work shares your blast radius. `status`
reports this as a `sharing :` line, and `request` warns at install time.

`revoke` ends only *your* grant. If the concern is another session, level 3 is
the one that covers both.

## Routine checks

- `~/.claude/bin/gcp-credentials status` — grant, identity, token age, refresh
  state, and whether an environment variable is overriding the token file. No
  secrets in its output, by construction; it is safe to run and safe to paste.
- A `STALE` token with a live grant means the refresh loop died, not that
  anything is wrong with the access — `refresh --background` fixes it and needs
  no human. Do not respond to it by requesting again; that spends an approval on
  a local process problem.
- `~/.claude/bin/gcp-credentials created` — the sandbox projects this client
  watched being created, scoped to the grant in hand. `end-session` reads it to
  surface a project the session's own approval brought into existence. Holds no
  secret; safe to run and safe to paste. `state=no-grant` means the question was
  never asked and is not the same answer as no projects.

## Verified end to end

The flow has been exercised for real work from a cloud sandbox (2026-08-12) and
from a local session. Findings from those runs are folded into the skill doc's
troubleshooting rather than kept here.
