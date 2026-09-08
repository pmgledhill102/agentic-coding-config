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

> created `<project>` — this repo's sandbox, built by this session's approval. Shared with every later session on the repo, and auto-deleted when its TTL lapses (7 days by default).

**Surface only. Never delete it, and never propose deleting it as tidy-up.**

That prohibition is the whole point of the step, so it is worth stating why rather than leaving it as a rule to be reasoned around, and there are two independent reasons.

**It is not yours to delete.** The broker resolves a repo to its sandbox project and creates one only when the repo has none, so the project belongs to the **repo**, not to the session that happened to be first. Every later session on that repo resolves to it, and another session may hold a live grant on it right now — the helper warns about exactly that. Deleting it would strand that work and cost the next session a fresh human approval plus the two-to-three minute provisioning wait, on the reasoning that this session made it: true, and irrelevant.

**There is nothing to clean up anyway.** A sandbox is created with a fixed TTL and a budget cap — today 7 days and £25/mo, composed by the broker and printed on the approval card — and a scheduled job deletes it when the TTL lapses. A grant is clamped to that expiry, which is why a 24h grant against a sandbox with 12h left comes back as 12h. So an unattended sandbox is not a leak accumulating cost: it is deleted, and capped in the meantime. Nothing at session end needs to act on it, which is precisely why this step reports and stops.

What the step is for, then, is neither cleanup nor cost: it is telling whoever caused shared infrastructure to exist that they did, at the one moment they are looking at it. If the sandbox should outlive its TTL, that is `/sandbox extend` during the work — capped at 30 days, and deliberately not automatic, since a sandbox extended on every use would never expire at all. Not a decision to take on the way out.

#### If the project genuinely should not exist

Wrong repo, an experiment abandoned, a sandbox built by a request that should never have been made. There is a route for that, and it is `gcp-credentials teardown`: one human approval on a card naming the project and every live grant on it, after which the broker revokes those grants and deletes the project. Name it **once**, beside the `created=` line, and in these words or near them:

> If that sandbox should not exist, `~/.claude/bin/gcp-credentials teardown` asks for it to be destroyed — one human approval, and this session's grant goes with it. Otherwise it expires on its own.

Then stop. What that line is, and what it is not:

- **It is not a recommendation, and the default is to leave the sandbox alone.** Everything above still holds: the project is the repo's, it costs nothing to leave, and it deletes itself. A step that reports a project and then nudges towards destroying it has argued itself out of its own reasoning in the space of four paragraphs.
- **Only beside a `created=` line.** A live grant on a sandbox this session did not build is someone else's project met in passing, and offering to destroy that is not this step's business — nor, at the end of a session, anybody's.
- **Never run it unprompted, and never run it to tidy up.** This is Tier 3: the user asks for it, or it does not happen. Approving one revokes every live grant on the sandbox including this session's own, which is why the helper stops the refresh loop and removes the token and grant files when it succeeds. It blocks until the human answers, so run it while there is still a session to answer in — not as the last thing before walking away.
