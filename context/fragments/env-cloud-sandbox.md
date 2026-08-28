# Cloud sandbox

True only in an ephemeral cloud sandbox. Nothing here applies on a
workstation, and the workstation fragment is never composed into a sandbox
profile — see ADR-0018 principle 5.

## This container is the whole environment

There is no chezmoi here, and `~/.claude/` is not chezmoi-managed. It is
written by `cloud/bootstrap.sh` when the environment is built, so a file
found there arrived with the container rather than from a workstation.

Anything installed by hand is lost when the container is reclaimed, and is
invisible to the next session. Changes that must survive belong in the repo
or in the environment's setup script.

## Capabilities available here

- **Brokered Google Cloud access**, when `CREDENTIAL_BROKER_URL` is set in
  the environment. Request it with the `gcp-credentials` skill rather than
  asking a human to run `gcloud` commands by hand. The trigger is not "I
  need to change something in GCP" but **"I am about to assert something
  about live GCP state"**.
- **Skills delivered by the bootstrap.** Those offered here are the whole set —
  a skill on the workstation but absent here was held back deliberately, not
  lost. Say that rather than improvising its behaviour from its name.

## `gh` is not installed here

GitHub work goes through the MCP tools. The `gh` CLI is absent from this
container, so a step that shells out to it fails rather than degrading — and
several do: `start-session` and `end-session` gather state through helper
scripts that call `gh`, and those sections report `gh-unavailable` on this
surface.

Treat a `gh` command written into a skill as naming the *operation*, not the
tool, and reach for the equivalent MCP call. Where a whole section depends on
it, say what could not be gathered rather than reporting a clean result.
