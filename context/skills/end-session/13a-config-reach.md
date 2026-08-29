### 7b. Did this session change what sandboxes install? (Tier 3 — surface, never act)

**Only fires in `agentic-coding-config`.** Elsewhere, skip silently — no other
repo is delivered by the cloud bootstrap.

A merge here does **not** reach cloud sessions. The environment snapshots its
setup script's result and re-runs it only when the script *text* changes, the
allowed domains change, or roughly seven days pass — and `REF=main` never
changes as a string, so new sessions keep restoring the snapshot built the
first time. Work that landed today can be invisible to every sandbox for a
week (`cloud/README.md:154`, #347).

Check whether anything the bootstrap delivers landed on the default branch
recently:

```sh
git log "origin/$DEFAULT_BRANCH" --since=1.day --name-only --pretty=format: -- \
    home/ profiles/ context/ cloud/bootstrap.sh | sed '/^$/d' | sort -u
```

- **No output**: skip silently. Nothing a sandbox installs has moved.
- **Any output**: add one line to the summary under "Needs attention":

  > `<N>` bootstrap-delivered path(s) changed on `<default>` — bump the `Rev:`
  > line in the environment setup script (claude.ai → environment settings), or
  > no new sandbox sees this for up to a week

**Surface only, and it has to be.** The `Rev:` field lives in the vendor's
settings UI, not in this repo, so no skill, no script and no merge can reach
it. Telling the human is the whole of the mechanism — which is exactly why it
gets a step rather than a footnote, and why leaving it to memory is how the
estate ends up running week-old config with nothing saying so.

Two properties worth naming rather than discovering later:

- **Deliberately over-inclusive.** A one-day window catches other people's
  merges and any commit that merely touches those trees. That is the right
  side to err on: a reminder that did not need firing costs one line, and one
  that fails to fire costs every sandbox up to a week of stale config.
- **It cannot tell whether the bump already happened.** Nothing readable from
  inside a container reports the current `Rev:`, so this asks rather than
  asserts. If it was already bumped, say so and move on.
