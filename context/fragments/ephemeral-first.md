# Ephemeral-first engineering

Portable policy, for any agent session on any surface. Agent sandboxes are
disposable: **how agents work must not depend on how long the environment
lives.** The reasoning behind each principle is in
[`docs/ephemeral-first.md`](https://github.com/pmgledhill102/agentic-coding-config/blob/main/docs/ephemeral-first.md).

1. **Environment-as-script.** Setup is committed, idempotent, and identical
   for a fresh environment and a resume. An install made mid-session to get
   unblocked is not finished until it is in the setup script, or in an issue
   asking for it.
2. **The repo is the default durable output channel, for what repos are
   for**: docs, scripts, code, configuration. Commit early rather than at the
   end. Datasets, fixtures, generated artifacts and bulk output do not belong
   in git; see 3.
3. **Durable storage is a separate, explicitly granted capability.** Never
   invent a location. If a task needs durable storage and none has been
   granted, say so and stop.
4. **Agent-built infrastructure checkpoints its state externally.** Remote
   state from the first `terraform init`, and the same for anything else that
   records what exists.

Before ending a session, ask: **if this environment were destroyed right
now, what would be lost?** Every answer is something that should have been
committed, something that needs a granted durable store, or something that
was never worth keeping.
