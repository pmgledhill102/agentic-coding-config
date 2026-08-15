Get GCP credentials for this session through the credential broker: request a human-approved grant, show the verification phrase the human must match, and install a short-lived token straight to disk. Use when a task needs GCP access and the session has none, or when a previously working grant has expired.

## When to use this

Reach for it when a GCP call fails for want of credentials, or before starting
work you already know needs them — `gcloud`, Terraform against a GCP provider,
a client library, anything that authenticates to Google Cloud.

Signals that this is the right move:

- `gcloud` reports no active account, or `ADC not found`
- an API call returns 401/403 and no grant is installed
  (`~/.claude/bin/gcp-credentials status` says `grant : none on this machine`)
- a grant that was working has expired — see [Grant expired](#grant-expired)

Do **not** request credentials speculatively. Every request pings a human on
Discord and burns a little of their willingness to read the card carefully. One
per session, when the work actually needs it.

## How it works, in one paragraph

The broker turns **one human approval into a grant** lasting 1–7 days. Inside
that window a background loop silently re-mints 1-hour GCP access tokens with no
further approvals. The human approves in Discord only if the card shows the same
three-word phrase as the session — that match is what binds an approval to
*this* session rather than to whichever request happened to arrive first. Design
and trust model: ADR 021 in `pmgledhill102/gcp-org-management`.

If the repo has no sandbox project yet, the same approval **also creates one**,
so the card may be authorising a project and its monthly spend as well as the
access. The build takes two to three minutes, during which the helper reports
`provisioning` — see [Waiting on a human, then waiting on
GCP](#waiting-on-a-human-then-waiting-on-gcp). Design: ADR 022.

## Requesting

```sh
~/.claude/bin/gcp-credentials request --purpose "stand up an Apigee instance and its supporting infra"
```

The project is resolved from the repo's `origin` remote, so nothing needs
configuring per project. Override with `--project <id>` if the broker cannot
resolve it, or `--repo <remote>` when working outside a checkout.

### Never ask the user which project to use

**The flow supplies the project. You do not choose it, and you must not ask the
user to.** On success the helper prints it, `gcloud` is already pointed at it,
and `status` reports it at any time.

This matters because repo scripts often carry a default project ID in a
`shared/env.sh` or similar, and it is tempting to ask which one to target. Asking
is wrong twice over: it interrupts the human for something already decided, and
their answer can send the work to a project the grant does not cover — the token
is scoped to one project, so a "helpful" override just produces permission
errors that look like a broken grant.

If the repo has no sandbox yet, the broker does not fail: approving the card
**creates one**, and the project it creates is the one to use. Wait for the
helper to report it rather than filling the gap with a guess or a question.

So: read the project from the helper's output, pass it to whatever needs it, and
say which project you are working in. Ask the user only if the helper exits
non-zero and the table below says to.

Useful options: `--ttl 72h` (1–7 days, default 24h), `--timeout 900`,
`--no-gcloud` if you only want the token file.

Write a **specific purpose**. It is the only thing the human has to judge the
request by, and it is rendered on the card as untrusted, agent-written text.
"deploy the Apigee bootstrap module to the sandbox" is approvable;
"do some GCP work" is not.

### Surface the phrase immediately

The command prints a block like this:

```text
==================================================================
  APPROVAL REQUIRED — verification phrase:

        mint-copper-falcon

  Approve in Discord ONLY if the card shows exactly this phrase.
==================================================================
```

`request` returns as soon as it has the phrase. It does **not** wait for the
decision, and that is deliberate: relay the phrase in your own reply, then
collect the answer separately.

Relay it **verbatim, as the first thing you say** — not buried in tool output.
Say what they are approving:

> Requesting GCP credentials for `pmgledhill-apix-sbx` (sandbox tier, 24h).
> **Verification phrase: `mint-copper-falcon`** — approve the Discord card only
> if it shows exactly that.

### Then collect the decision

```sh
~/.claude/bin/gcp-credentials wait
```

This blocks until the human answers, then installs the token and starts refresh.

**Never collapse these two steps into one.** `request --wait` exists for a human
at an interactive terminal and is wrong for you: a blocked command cannot
produce a reply, so the phrase would sit unread in the output of something still
running while the human is asked to match it against nothing. The phrase is only
a session binding if it reaches the person *before* they answer the card. Run
them as two turns, with your message carrying the phrase in between.

If the session scrolls or you lose track, `status` reports the outstanding
request and its phrase.

### Waiting on a human, then waiting on GCP

`wait` distinguishes two waits, and it is worth relaying which one you are in.
Before the decision it reports waiting for approval — that is the one a nudge in
Discord can help with. After approval it may report:

```text
  approved — waiting for the agent identity to become usable (GCP propagation, usually under a minute)
```

Nothing is wrong there and nobody needs chasing. The broker refuses to hand over
a grant it cannot actually mint a token for, so it waits for the identity to
propagate rather than issuing something that would fail on first use. It
resolves on its own, without a second approval. Say so if asked, and wait.

When the repo had no sandbox, there is a longer wait first, while the project is
built:

```text
  approved — creating the sandbox project (this takes two to three minutes)
```

Also normal, also nobody to chase. **Do not fill the time by asking the user
which project to target** — that is what this wait is deciding. Tell them the
sandbox is being created and roughly how long it takes, and wait. If it never
appears the helper exits non-zero and the reason is posted to the operations
channel by the service that built it.

## Reading the outcome

| Exit | Meaning | What to do |
| --- | --- | --- |
| 0 | Installed | Carry on. Say which project and when the grant expires. |
| 2 | Usage error | Fix the arguments. |
| 3 | **Denied** or revoked | Stop. A human said no. Do not re-request without asking them why. |
| 4 | Timed out / expired | Nobody answered, which the broker treats as a deny. Ask the user before retrying. |
| 5 | Rate limited | Wait. Do not loop. |
| 6 | Not configured | No request key or no broker URL — see [Setup](#setup-not-per-session). |
| 7 | Approved, but the identity never became usable | **Not a deny** — nobody refused. Report the reason the helper printed. Requesting again is legitimate; if it recurs, say so, because the sandbox's agent identity needs attention. |
| 8 | This helper is too old for the broker | Relay the remedy the helper printed and **stop**. Retrying cannot help — nothing is wrong with the request, the client simply cannot speak the current contract. |
| 1 | Broker unreachable or mint failed | Report it. Do not proceed as if credentials exist. |

Exit 7 is worth distinguishing from exit 3 in what you tell the user. A deny is a
decision and asking again without checking is rude; a failure is a fault, and
retrying is the reasonable response.

Exit 8 is neither. Nothing is wrong with the request and nobody decided
anything — this helper predates a change to the broker's contract and cannot
speak it. The broker refuses **before** posting a card, so no approval was spent
and none will be until the helper is updated. Relay the remedy it printed
(`chezmoi apply` locally, or bump `Rev:` in the cloud setup script) and stop;
retrying is the one thing that certainly will not help.

Never carry on without credentials after a non-zero exit. Silently falling back
to whatever identity happens to be lying around is the exact failure the broker
exists to prevent.

## After a successful request

Report only what the helper printed:

> Credentials installed for `pmgledhill-apix-sbx`, grant expires 2026-08-13T11:33Z.
> Background refresh is running.

`gcloud` is pointed at the token through a dedicated `agent-broker`
configuration, which is activated. `~/.claude/bin/gcp-credentials release`
restores the configuration that was active before.

### If the project was just created: early 403s are propagation

When the sandbox was built by this very approval, the helper says so and warns
that API enablement and IAM bindings are still propagating. **A 403 or 404 on
your first calls is propagation, not misconfiguration.** Wait ~60 seconds and
retry once before diagnosing anything — and do **not** modify IAM or org policy
to work around it. You hold `roles/owner`; "fixing" a propagation delay by
granting things is how a sandbox's permissions end up unrecognisable.

### The grant may be shorter than you asked for

A grant is clamped to the sandbox's own expiry — a 24h grant against a sandbox
that is deleted in 12h becomes a 12h grant, and the approval card said so. If
the helper reports a shorter expiry than requested, that is why; it is not an
error. A sandbox expiring within the hour is refused at request time with a
pointer at `/sandbox extend` — relay that to the user rather than retrying.

### Someone else may be working in the same project

Sandboxes are shared per repo. If the helper prints a `WARNING` about other
active grants — or `status` shows a `sharing :` line — another session holds a
live grant on the same project, under the same identity, at `roles/owner`.
Nothing prevents you overwriting each other's work. **Tell the user before any
destructive operation** (`terraform destroy`, deleting resources, rewriting
state): they may be running the other session themselves and know what it is
doing.

## Things never to do

- **Never print, `cat`, `grep`, `head` or otherwise read the token file.** The
  whole design rests on the credential not entering the transcript. The helper
  writes it from the HTTP response to disk without it passing through a shell
  variable; reading it back undoes that in one tool call.
- **Never run `gcloud auth print-access-token`** (or `print-identity-token`, or
  `terraform output` on anything holding a token). Same reason.
- **Never read `~/.config/gcloud`.** On a local machine that directory holds the
  human's own long-lived admin refresh token. It is not yours, it is not scoped,
  and it is not an hour long. If the broker path fails, the answer is to report
  the failure, not to reach around it.
- **Never ask the user to paste a token, key, or service-account JSON into the
  session.** Anything pasted is in the transcript forever. If credentials are
  needed, they come through the broker.
- **Never pass the request key on a command line.** The helper reads it from the
  environment or a 0600 file for a reason; `--key`-style arguments are visible in
  process listings.
- **Never re-request after a deny** without the user telling you to.

For a tool that needs the token in an environment variable rather than a file,
feed it from the file in the same command and never echo it:

```sh
GOOGLE_OAUTH_ACCESS_TOKEN="$(cat ~/.config/claude/credential-broker/access_token)" terraform plan
```

## An authentication failure? Run `renew` first, then think

**Before diagnosing any GCP authentication error, run:**

```sh
~/.claude/bin/gcp-credentials renew
```

If it succeeds, the problem is solved and there was nothing to diagnose. It
costs one HTTP call, needs no human, and is a no-op you can afford to be wrong
about.

The reason is that the background refresh loop is **not reliable in a sandbox**.
Detached processes are reaped there — observed twice in one session, once across
an idle gap and once inside a twenty-minute window of active work. When that
happens the grant stays valid for days while the token quietly ages out, so the
first symptom is an authentication error that looks like a broker fault, an IAM
problem, or a revoked grant, and is none of them.

Applies to `Request had invalid authentication credentials`, a bare 401 or 403
from a Google API, and `Unable to read file [...access_token]`. The last one
means the token was *removed*, not rejected — a grant that ended, or a `release`
— and `renew` will tell you which by failing with an exit code that says so.

Escalate only if `renew` itself fails:

- exit 4 — the grant is genuinely over; request a new one
- exit 2 — no grant on this machine at all; request one
- exit 1 — the broker is unreachable, which is a real fault worth reporting

## After a container restart or a resumed session

**Check this before anything else in a resumed cloud session.** Sandboxes
restart container processes across an idle gap: the filesystem survives — your
installed tools, the token file, the log — but the background refresh loop does
not. Nothing restarts it, so the token ages out and dies while the grant is
still perfectly valid.

Symptoms, in the order you meet them:

- `gcloud` fails with `Request had invalid authentication credentials`
- `~/.claude/bin/gcp-credentials status` shows a live grant, `refresh : not
  running`, and a token flagged stale:

  ```text
  token   : present at ~/.config/claude/credential-broker/access_token (minted 2h 11m ago — STALE, past its 3600s lifetime)
            nothing has minted since, so the refresh loop is probably dead:
            'gcp-credentials refresh --background' mints now and restarts it
  ```

`status` derives that age from the token file's mtime, so it is reporting when a
token was last successfully minted — not merely that a file exists. A `STALE`
line is the answer on its own; there is no need to read the refresh log to
confirm it, and no reason to go looking at IAM.

The fix needs **no human approval** — the grant is what a human approved, and it
has not expired:

```sh
~/.claude/bin/gcp-credentials refresh --background
```

That mints a token immediately and resumes the loop.

**Do not run `request` for this.** It pings a human for an approval that is not
needed, spending the one genuinely scarce resource in this design to fix a local
process problem. Requesting again is for an expired *grant*, not a dead loop —
`status` tells you which you have.

`renew` mints once and exits, without touching the loop, when that is all you
want.

## Grant expired

The grant, not the token, is what runs out. Symptoms:

- `~/.claude/bin/gcp-credentials status` shows `token : none installed`, or a
  grant whose expiry is in the past
- `gcloud` fails with a missing-token-file error
- the refresh log ends with `grant expired; token removed`

That is the designed end of the window, not a fault. Request again — a fresh
approval, a fresh phrase — and tell the user that is what you are doing:

> The 24h grant expired. Requesting a new one; new phrase: `willow-basalt-heron`.

Do not diagnose it as an auth bug, and do not go looking for another credential.

## Other subcommands

```sh
~/.claude/bin/gcp-credentials status    # grant, token, refresh, gcloud — no secrets
~/.claude/bin/gcp-credentials release   # drop the token locally, keep the grant
~/.claude/bin/gcp-credentials revoke    # end the grant at the broker as well
```

`status` and `release` are pre-approved in `settings.json`; `request` and
`revoke` prompt, because both reach the broker and one of them pings a human.

Run `release` when finishing a session on a shared/local machine, so the human's
gcloud configuration goes back to theirs. Run `revoke` when the access should
end outright — after finishing a piece of work early, or if anything about the
session looks wrong.

## Setup (not per session)

Two things are machine or environment properties, configured once, never pasted
into a session:

| What | Cloud sandbox | Local macOS |
| --- | --- | --- |
| Request key | `$CREDENTIAL_BROKER_REQUEST_KEY` | `~/.config/claude/credential-broker/request-key`, mode 0600 |
| Broker URL | `$CREDENTIAL_BROKER_URL` | `~/.config/claude/credential-broker/url` |

Exit 6 names both locations. If a machine is missing them, that is a setup task
for the human — say so and stop; do not attempt to work around it.

### Cloud sandboxes also need the broker on the network allowlist

A cloud sandbox reaches only allowlisted domains. The **Trusted** default list
covers `*.googleapis.com`, so GCP API calls work once a token is installed — but
it does **not** cover the broker's own host, which is a `*.run.app` address. Add
it under **Custom** network access, with the default list still included:

```text
credential-broker-<hash>-nw.a.run.app
```

Without it the request fails at the network layer, which reads as the broker
being down rather than as an environment that was never allowed to call it.

`gcloud` is not pre-installed in a cloud sandbox (`jq` and `git` are). If a task
needs it, `dl.google.com` — the SDK download host — also has to be allowlisted;
neither `cloud.google.com` nor `gcloud.google.com`, both of which are on the
default list, serve the tarball. Install it from the **environment's setup
script** rather than mid-session, because `gcp-credentials request` only wires
up a gcloud configuration if gcloud exists at the moment it runs. Installed
afterwards, gcloud is left pointing at nothing and the fix costs a second human
approval.

## Approval hygiene, for the human

Worth restating when relaying a phrase, because it is the only real defence:

- Approve **only** if the card's phrase matches the session's, character for
  character.
- A card arriving with no session running is grounds to deny, always.
- The purpose text on the card is written by an agent and is marked untrusted.
  Project, identity, tier and duration are composed by the broker and can be
  relied on.
