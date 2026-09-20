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

For each `created=` line, surface three things in one block — what exists, why this session is leaving it, and the one route that would remove it:

> created `<project>` — this repo's sandbox, built by this session's approval. Shared with every later session on the repo, and auto-deleted when its TTL lapses (7 days by default).
>
> Leaving it because `<this session's own read: the work it was built for is ongoing / it is the repo's only sandbox / nothing about how it came to exist looks like a mistake>`.
>
> If that read is wrong, `~/.claude/bin/gcp-credentials teardown` asks for it to be destroyed — one human approval, and this session's grant goes with it. Otherwise it expires on its own.

All three lines, every time, for a sandbox **this session created**. The middle line is the point of the change: the decision to leave the project is being made either way, and saying it out loud is what makes it cheap to overrule in a word ([#414](https://github.com/pmgledhill102/agentic-coding-config/issues/414)).

**Surface only. Never delete it, and never propose deleting it as tidy-up.** Naming a route is not proposing it — see below.

That prohibition is the whole point of the step, so it is worth stating why rather than leaving it as a rule to be reasoned around, and there are two independent reasons.

**It is not yours to delete.** The broker resolves a repo to its sandbox project and creates one only when the repo has none, so the project belongs to the **repo**, not to the session that happened to be first. Every later session on that repo resolves to it, and another session may hold a live grant on it right now — the helper warns about exactly that. Deleting it would strand that work and cost the next session a fresh human approval plus the two-to-three minute provisioning wait, on the reasoning that this session made it: true, and irrelevant.

**There is nothing to clean up anyway.** A sandbox is created with a fixed TTL and a budget cap — today 7 days and £25/mo, composed by the broker and printed on the approval card — and a scheduled job deletes it when the TTL lapses. A grant is clamped to that expiry, which is why a 24h grant against a sandbox with 12h left comes back as 12h. So an unattended sandbox is not a leak accumulating cost: it is deleted, and capped in the meantime. Nothing at session end needs to act on it, which is precisely why this step reports and stops.

What the step is for, then, is neither cleanup nor cost: it is telling whoever caused shared infrastructure to exist that they did, at the one moment they are looking at it. If the sandbox should outlive its TTL, that is `/sandbox extend` during the work — capped at 30 days, and deliberately not automatic, since a sandbox extended on every use would never expire at all. Not a decision to take on the way out.

#### Why the route is named every time

`gcp-credentials teardown` is one human approval on a card naming the project and every live grant on it, after which the broker revokes those grants and deletes the project. It is the only route, and the cases that want it are real: wrong repo, an experiment abandoned, a sandbox built by a request that should never have been made.

This step used to name it **conditionally** — "if the project genuinely should not exist". The condition did no work, because the only party positioned to judge it is the session doing the reporting, and under a conditional that session judges silently: it prints the project, decides the condition does not hold, and stops. The read is made either way; what the condition removed was the chance to disagree with it. So the route is named unconditionally and the read is stated beside it, which changes what is printed and not what is done.

Then stop. What those lines are, and what they are not:

- **They are not a recommendation, and the default is to leave the sandbox alone.** Everything above still holds: the project is the repo's, it costs nothing to leave, and it deletes itself. A step that reports a project and then nudges towards destroying it has argued itself out of its own reasoning in the space of four paragraphs. The middle line exists to make the default visible, not to soften it.
- **Only beside a `created=` line.** A live grant on a sandbox this session did not build is someone else's project met in passing, and offering to destroy that is not this step's business — nor, at the end of a session, anybody's.
- **Never run it unprompted, and never run it to tidy up.** This is Tier 3: the user asks for it, or it does not happen. Approving one revokes every live grant on the sandbox including this session's own, which is why the helper stops the refresh loop and removes the token and grant files when it succeeds. It blocks until the human answers, so run it while there is still a session to answer in — not as the last thing before walking away.
