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

## Requesting

```sh
~/.claude/bin/gcp-credentials request --purpose "stand up an Apigee instance and its supporting infra"
```

The project is resolved from the repo's `origin` remote, so nothing needs
configuring per project. Override with `--project <id>` if the broker cannot
resolve it, or `--repo <remote>` when working outside a checkout.

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

Relay the phrase to the user **verbatim, in your own reply, as the first thing
you say** — do not leave it buried in tool output. Say what they are approving:

> Requesting GCP credentials for `pmgledhill-apix-sbx` (sandbox tier, 24h).
> **Verification phrase: `mint-copper-falcon`** — approve the Discord card only
> if it shows exactly that.

Then let the command keep polling. It exits by itself on a decision.

## Reading the outcome

| Exit | Meaning | What to do |
| --- | --- | --- |
| 0 | Installed | Carry on. Say which project and when the grant expires. |
| 2 | Usage error | Fix the arguments. |
| 3 | **Denied** or revoked | Stop. A human said no. Do not re-request without asking them why. |
| 4 | Timed out / expired | Nobody answered, which the broker treats as a deny. Ask the user before retrying. |
| 5 | Rate limited | Wait. Do not loop. |
| 6 | Not configured | No request key or no broker URL — see [Setup](#setup-not-per-session). |
| 1 | Broker unreachable or mint failed | Report it. Do not proceed as if credentials exist. |

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

## After a container restart or a resumed session

**Check this before anything else in a resumed cloud session.** Sandboxes
restart container processes across an idle gap: the filesystem survives — your
installed tools, the token file, the log — but the background refresh loop does
not. Nothing restarts it, so the token ages out and dies while the grant is
still perfectly valid.

Symptoms, in the order you meet them:

- `gcloud` fails with `Request had invalid authentication credentials`
- `~/.claude/bin/gcp-credentials status` shows a live grant, `token : present`
  (but stale), and `refresh : not running`
- the refresh log's last entry is hours old

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

## Approval hygiene, for the human

Worth restating when relaying a phrase, because it is the only real defence:

- Approve **only** if the card's phrase matches the session's, character for
  character.
- A card arriving with no session running is grounds to deny, always.
- The purpose text on the card is written by an agent and is marked untrusted.
  Project, identity, tier and duration are composed by the broker and can be
  relied on.
