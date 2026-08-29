### 5b. Is this container running current config? (Tier 1 — surface, never act)

From gather section `bootstrap_currency`. A cloud environment restores a
filesystem snapshot and re-runs its setup script only when the script text
changes, the allowed hosts change, or roughly seven days pass — so pushing to a
branch does not reach new sessions, and a sandbox can be running week-old
skills, policy and helper scripts with nothing saying so.

- **`state=failed`**: the bootstrap **died partway** and this container holds
  an unknown subset of the skills, helpers, hooks and policy it should. Report
  it first and on its own, above every other line in the brief, with `step=`,
  `exit_code=` and `log=` verbatim — then stop and let the human decide, rather
  than working around whatever turns out to be missing. Nothing else in the
  brief is trustworthy while this is set: a container this far from what it
  claims to be will misreport in ways that look like ordinary absence. Treat a
  missing skill, command or helper for the rest of the session as unproven, not
  as evidence the machine does not do that thing.
- **`state=current`**, **`state=no-manifest`**: silent. `no-manifest` is a
  container built before manifests existed; it self-heals when the snapshot
  next expires. It does **not** mean a crashed run — a failed bootstrap writes
  `status=failed` rather than nothing (#345), so absence again means only what
  it used to.
- **`state=pinned`**: names the ref the environment froze to. Report only if
  something else looks stale.
- **`degraded=<names>`**: an extra line that can accompany **any** state above,
  including `current` — the bootstrap's Tier 2 capabilities (gcloud,
  pre-commit and its linters, gh) install after the toolkit and degrade rather
  than abort, so a container can be entirely up to date and still missing one.
  Surface it as one line under "Needs attention" naming what is missing. It is
  not `state=failed` and must not be reported as a broken container: the
  toolkit is present, one toolchain is not. What it changes is what you may
  conclude from a later absence — a lint or scan that cannot run here is
  unverified work to report, never a gate that passed.
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

That second limit bites hardest on `state=failed`, because this skill is
installed near the end of the bootstrap: a failure early enough takes the
reporting away with everything else, and there is no `start-session` left to
run. That case is covered outside this skill — the same trap that writes the
manifest prepends a banner to `~/.claude/CLAUDE.md` and `~/.agents/AGENTS.md`,
which are read whether or not any skill survived. So a banner and this section
are two views of one event: if you have already seen the banner, do not report
it twice.

**Never re-run the bootstrap unasked, and never offer to as a Tier 1 action.**
This is surface-only by design: reinstalling the harness the agent is running
inside, mid-session, without the human reading what changed, is its own hazard.
