# Ephemeral-first engineering

Portable policy. Applies to any agent session, on any surface.

Agent sandboxes are disposable, and their lifetime is becoming a tunable
rather than a fixed assumption. The governing principle is **decoupling: how
agents work must not depend on how long the environment lives.** At a long
TTL, in-place continuity is a convenience; at a short one, nothing about the
workflow should change.

The same forcing function ephemeral CI runners applied to builds applies
here. When the environment dies regularly, reproducibility stops being
discipline and becomes physics.

## 1. Environment-as-script

Setup is **committed, idempotent, and identical for a fresh environment and
a resume.** The contents of a sandbox must be reconstructible from the repo.

- Anything installed by hand is lost, and worse, invisible: the next session
  starts subtly different from this one and nobody knows why
- "Idempotent" is not optional. The same script runs on a cold start and on
  a resume, so every step has to tolerate already having been done
- If you install something mid-session to get unblocked, the work is not
  finished until that install is in the setup script — or in an issue asking
  for it. A session that only works because of what you typed into it is a
  session that cannot be repeated

## 2. The repo is the default durable output channel — for what repos are for

Docs, scripts, code, configuration. Commit early rather than at the end: an
uncommitted change is one reclaimed container away from never having existed.

It is **not** the channel for testing datasets, fixtures, generated
artifacts, or bulk output. A repo used as a filesystem stops being reviewable
and starts being a place things go to be forgotten. If the thing is large,
binary, regenerable, or uninteresting to a reviewer, it does not belong in
git — see principle 3.

## 3. Durable storage is a separate, explicitly granted capability

Anything that must outlive the sandbox goes somewhere granted for the
purpose. **Never assumed.**

- Do not invent a location. A bucket, a volume, or a database that a session
  decided on unilaterally is one nobody else knows to look in, nobody is
  paying attention to, and nobody has scoped access for
- If a task needs durable storage and none has been granted, say so and stop,
  the same way a task needing credentials says so and stops. "I put it
  somewhere" is not an answer
- Absence of a granted store is a finding worth reporting, not an obstacle to
  route around

## 4. Agent-built infrastructure checkpoints its state externally

Terraform state written inside a disposable environment means every
re-provision starts with archaeology — reconciling real cloud resources
against a state file that died with its container.

- Remote state from the first `terraform init`, not once it hurts
- The same holds for anything else that records what exists: migration
  version tables, deployment ledgers, resource inventories
- State that lives only in the sandbox converts a routine re-provision into
  an incident

## What this means in practice

Before ending a session, ask: **if this environment were destroyed right
now, what would be lost?** Every answer is either something that should have
been committed, something that needs a granted durable store, or something
that was never worth keeping. There is no fourth category, and "it is fine,
the sandbox will still be here" is not one of the three.
