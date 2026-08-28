### 14. GCP sandbox project created this session (Tier 3 — surface only)

From gather section `gcp_projects`. The first line is `state=`:

| `state=` | What it means | Report |
| --- | --- | --- |
| `no-grant` | No grant was held, so the question was never asked | `n/a (no GCP grant this session)` |
| `grant`, no `created=` lines | A grant was held and built nothing | `none` |
| `grant`, with `created=` lines | This session's approval built the repo's sandbox project | surface each, below |
| `helper-unavailable` | The broker client is not installed here | `n/a (broker client absent)` |
| `helper-too-old` | The installed broker client predates this step | `n/a (broker client predates this check)` |

**Never report `none` for `no-grant`.** They are different answers: one says nothing was created, the other says nothing was checked. Collapsing them turns "I did not look" into "there is nothing there", which is the silent-absence failure #239 exists for.

`helper-too-old` is not a fault. A container pins the broker client at the SHA its bootstrap ran, while this skill arrives with whatever composed it, so a session can hold a helper that has never heard of this check. It resolves itself when the container next picks up current config, and until then the honest report is that the question could not be asked — not that nothing was created.

For each `created=` line, surface:

> created `<project>` — this repo's sandbox, built by this session's approval. Shared with every later session on the repo, and already scheduled to expire.

**Surface only. Never offer to delete it, and never delete it.**

That prohibition is the whole point of the step, so it is worth stating why rather than leaving it as a rule to be reasoned around, and there are two independent reasons.

**It is not yours to delete.** The broker resolves a repo to its sandbox project and creates one only when the repo has none, so the project belongs to the **repo**, not to the session that happened to be first. Every later session on that repo resolves to it, and another session may hold a live grant on it right now — the helper warns about exactly that. Deleting it would strand that work and cost the next session a fresh human approval plus the two-to-three minute provisioning wait, on the reasoning that this session made it: true, and irrelevant.

**There is nothing to clean up anyway.** A sandbox carries its own expiry and the broker deletes it when it lapses; a grant is clamped to that expiry, which is why a 24h grant against a sandbox with 12h left comes back as 12h. So an unattended sandbox is not a leak accumulating cost — it is a thing already scheduled to disappear. Nothing at session end needs to act on it, which is precisely why this step reports and stops.

What the step is for, then, is neither cleanup nor cost: it is telling whoever caused shared infrastructure to exist that they did, at the one moment they are looking at it. If the sandbox should outlive its expiry, that is `/sandbox extend` during the work, not a decision to take on the way out.

If the project genuinely should not exist — wrong repo, an experiment abandoned — that is a deliberate teardown someone does knowing what else depends on it, not a tidy-up at the end of a session.
