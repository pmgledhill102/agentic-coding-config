### 5b. Is this container running current config? (Tier 1 — surface, never act)

From gather section `bootstrap_currency`. A cloud environment restores a
filesystem snapshot and re-runs its setup script only when the script text
changes, the allowed hosts change, or roughly seven days pass — so pushing to a
branch does not reach new sessions, and a sandbox can be running week-old
skills, policy and helper scripts with nothing saying so.

- **`state=current`**, **`state=no-manifest`**: silent. `no-manifest` is a
  container built before manifests existed; it self-heals when the snapshot
  next expires.
- **`state=pinned`**: names the ref the environment froze to. Report only if
  something else looks stale.
- **`state=behind`**: say so plainly at the top of the brief and give the
  remedy verbatim from `remedy=`. Re-running the bootstrap takes effect
  immediately and needs no restart. Everything the container delivers —
  skills, policy, helpers — is as old as that SHA, which is why this is worth
  a line of its own rather than a footnote.
- **`state=unknown`**: the ref could not be resolved (no network). Mention it
  once; do not retry.

Two honest limits, worth knowing rather than implying more than it does. The
check ships inside the thing it checks, so a container older than the check
cannot report it — that resolves itself after one cache cycle, not immediately.
And this runs only when this skill runs; it is advisory, not a guarantee.

**Never re-run the bootstrap unasked, and never offer to as a Tier 1 action.**
This is surface-only by design: reinstalling the harness the agent is running
inside, mid-session, without the human reading what changed, is its own hazard.
