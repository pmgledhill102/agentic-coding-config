# Read-only observability grant on staging/prod — the same Discord approval, a different tier

Status: parked (2026-11-14)
Trigger: A staging or prod defect the `readonly-estate` tier cannot diagnose: it needs `errorreporting`/`cloudtrace` access, or per-project scope rather than org-wide
From: pmgledhill102/agentic-coding-config#236

## Problem

The expected engineering flow for a formal repo is: develop in the repo's
**sandbox** project, with a broker grant at `roles/owner` on that one project
(#140, ADR 021/022 in `gcp-org-management`). That part is fine and works.

It has no answer for **fixing something that only manifests in staging or
prod**. The evidence — logs, error groups, traces, revision history — lives in
a project the session cannot see, and the grant is deliberately scoped to a
project where the bug does not happen.

Every route available today is bad:

- **Human copy-pastes log lines into the session.** Slow, lossy (the agent
  cannot follow the trace or widen the time window without another round
  trip), and it puts production log payloads into a transcript permanently.
- **Agent works from a prose description of the failure.** This is the
  3-strikes rule waiting to happen, on the one class of bug where guessing is
  least likely to land.
- **Someone reaches for a broader credential** — a resident admin login, a
  wider grant "just for a minute". That is precisely the standing-credential
  failure the broker exists to remove, and it will be reached for at the
  moment the human is most frustrated.

## Proposal

A **second grant class through the existing framework** — same helper, same
request → phrase → Discord card → approve → grant → silent 1-hour tokens
written to disk. Nothing about the mechanism is new; the whole point is that
it is not new. What differs:

| | Sandbox grant (today) | Observer grant (proposed) |
| --- | --- | --- |
| Target project | the repo's sandbox, resolved from `origin` | a named **staging or prod** project |
| Roles | `roles/owner` | fixed read-only observability bundle |
| Writes | expected | **refused by the broker**, whatever is requested |
| TTL | 1–7 days | hours, defaulting short |
| Card | routine | visibly distinct, so approving prod read is never muscle memory |

The card already says "sandbox tier", so a tier concept exists to extend
rather than invent.

### Role bundle sketch

- `roles/logging.viewer` — **not** `privateLogViewer`, which adds data-access
  logs and their payloads
- `roles/monitoring.viewer`
- `roles/errorreporting.viewer`
- `roles/cloudtrace.user` (read spans)
- possibly a deploy-surface viewer (e.g. `roles/run.viewer`) so a log line can
  be correlated to the revision that produced it

Explicitly **excluded**: every data-plane read — Storage objects, BigQuery
data, Firestore documents, Secret Manager. "Read-only" is not the boundary
that matters here; "no customer data" is.

Residual risk stated honestly: **log entries themselves can carry PII and
secrets.** That is not fixable by role selection, and it is the reason the
grant is short, the card is loud, and the rule below exists.

## Design questions to settle

1. **New tier or new verb?** `request --tier observer --project <staging>`
   versus a distinct subcommand. Tier is the smaller change and reuses the
   card layout; a distinct verb is harder to invoke by accident.
2. **How does the broker know a repo's staging/prod projects?** Today the
   project is resolved from the `origin` remote to *the sandbox*. Anything
   else needs a repo → environment → project mapping, which is the same
   declarative registry proposed in #232 ("access control as code"). This
   issue is probably **blocked on that**, and should not grow its own
   one-off mapping file.
3. **Two live grants at once.** The session would hold owner-on-sandbox and
   viewer-on-prod simultaneously. The helper installs *one* token file and
   activates *one* gcloud configuration, and `request` currently exits 2 when
   a live grant exists. Concurrent grants are a real client-side change —
   named configurations, or an explicit swap — not a broker-only feature.
4. **Write-refusal belongs in the broker, not the client.** A non-sandbox
   project should be un-mintable with any write scope regardless of what the
   request asks for, so a confused or injected session cannot escalate by
   argument.
5. **Is the read itself audited back to the human?** GCP audit logs attribute
   the API calls to the agent SA, which covers the forensic case. Whether a
   short summary should also land in the ops channel is a separate call.
6. **Data-handling rule for the agent, in the skill.** Quote the minimum line
   count needed to explain the fix; never paste raw prod log output wholesale
   into the transcript, a PR body, or an issue. A public GitHub issue full of
   production log lines is an exfiltration path that needs no attacker.

Consistent with [ADR-0016](https://github.com/pmgledhill102/agentic-coding-config/blob/main/adrs/0016-capability-delivery-principles.md)
principle 2: this is an **environment capability**, so a repo gaining it
commits nothing.

## Is the need real? — the honest part

**No task has actually needed this yet**, which is why this is P3 and a design
issue rather than a build.

The one candidate is **`automated-trains`**: it reads Gmail for source
material and Calendar for its output, so both ends of that pipeline are
visible — but it is unclear how its *logs* have ever been read, and unclear
whether that repo follows the standards laid out here at all. Checking that is
the first step, because the answer decides what this issue is:

- Human reads Cloud Console by hand and pastes → **this is the motivating
  case**, promote it.
- The agent already has some standing credential → **that is a finding on its
  own**, more urgent than this feature, and it belongs in #232's audit.
- Nothing has ever needed logs → leave this parked, no harm done.

## Acceptance criteria

A **recorded decision**, not code: either the broker design extended with an
observer tier (issue or ADR text, whichever the shape warrants), or an
explicit rejection with the reason. Plus the `automated-trains` check above
answered one way or the other.

## Related

- #140 — the broker design this extends
- #232 — the repo → project → permission registry question 2 depends on
- ADR 021 / 022 in `pmgledhill102/gcp-org-management` — grant and sandbox design
