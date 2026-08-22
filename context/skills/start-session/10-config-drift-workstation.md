### 5b. Deployed-config drift (Tier 1 — surface, never act)

From gather section `claude_drift`. Answers a question nothing else asks: does
`~/.claude/` on this machine still match what the repo says it should be?

A chezmoi-managed file can be fixed in the repo and go on running the old
version here for as long as nobody applies. The failure is not forgetting to
apply — it is that nothing distinguishes "this machine is current" from "this
machine is a day behind", so there is nothing to forget about. It has already
cost a session: two merged commits to `bin/gcp-credentials` were undeployed
while the cloud surface had them, so local and cloud disagreed on the behaviour
of a security control and an issue was filed against a defect already fixed.

- **`state=no-source`**: silent skip. Outside an a-c-c checkout there is
  nothing to compare against without a network fetch, which is not worth every
  session start.
- **`behind=0 modified=0`**: silent. This is the normal case and should stay
  invisible.
- **`behind >= 1`**: surface under **Needs attention** in the brief, naming the
  count and the files, with the remedy verbatim from `remedy_behind`. The
  command is `chezmoi apply --refresh-externals`, **not** a plain `chezmoi
  apply` — the archive external's 168h refresh period means a plain apply can
  re-serve the cached copy.
- **`modified >= 1`**: surface separately, and do not conflate it with the
  above. A hand-edited file in `~/.claude/` is a different problem with a
  different fix — the edit is lost on the next apply, so it needs moving into
  the repo. Reporting both as one number makes the message ignorable.

**Never apply anything, and never offer to.** This is Tier 1 surface-only by
design: applying config changes under an agent without the human reading them
is its own hazard, and this repo deploys the harness the agent is running
inside.
