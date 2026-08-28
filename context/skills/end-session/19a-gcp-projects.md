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

> created `<project>` — this repo's sandbox, built by this session's approval. Shared, durable, and carrying monthly spend.

**Surface only. Never offer to delete it, and never delete it.**

That prohibition is the whole point of the step, so it is worth stating why rather than leaving it as a rule to be reasoned around. The broker resolves a repo to its sandbox project and creates one only when the repo has none. The project therefore belongs to the **repo**, not to the session that happened to be first: every later session on that repo resolves to the same project, and other sessions may hold live grants on it right now. Deleting it at session end would take out shared infrastructure that nothing else recreates, on the reasoning that this session made it — which is true and irrelevant.

What this step is for is the other half of that fact. An approval can authorise a project *and its ongoing monthly spend*, and the session that caused it is the one walking away minutes later. Naming it here puts the commitment in front of the person who made it, at the one moment they are looking.

If the project genuinely should not exist — wrong repo, an experiment abandoned — that is a deliberate teardown someone does knowing what else depends on it, not a tidy-up at the end of a session.
