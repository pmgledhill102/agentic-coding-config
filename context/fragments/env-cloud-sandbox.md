# Cloud sandbox

True only in an ephemeral cloud sandbox. Nothing here applies on a
workstation, and the workstation fragment is never composed into a sandbox
profile — see ADR-0018 principle 5.

## This container is the whole environment

There is no chezmoi here, and `~/.claude/` is not chezmoi-managed.
`cloud/bootstrap.sh` writes most of it at build time, but the platform
launcher writes there too and refreshes its files each session, so presence
says nothing about age or owner — `~/.agents/.bootstrap-manifest` lists ours.

Anything installed by hand dies with the container and is invisible to the
next session. What must survive belongs in the repo or the setup script.

## Capabilities available here

- **Brokered Google Cloud access**, when `CREDENTIAL_BROKER_URL` is set in
  the environment. Request it with the `gcp-credentials` skill rather than
  asking a human to run `gcloud` commands by hand. The trigger is not "I
  need to change something in GCP" but **"I am about to assert something
  about live GCP state"**.
- **Skills delivered by the bootstrap.** Those offered here are the whole set —
  a skill on the workstation but absent here was held back deliberately, not
  lost. Say that rather than improvising its behaviour from its name.

## `gh` is a property of the setup line

GitHub work goes through the MCP tools. `gh` is present only when the setup
line passes `--with-gh`, and GraphQL is blocked for every Claude Code session
whatever the binary's state, so `gh pr view`, `gh pr list` and review-thread
commands fail; REST reads have been seen to work. Verify, never assume. Helpers
that shell out to `gh` report `gh-unavailable` or `gh-unauthorized`: say what
could not be gathered rather than reporting a clean result, and treat a `gh`
command written into a skill as naming the *operation* — reach for the MCP
call. In a **child session** every `claude-code-remote` call fails to bind its
approval (anthropics/claude-code#90127): prefer event-driven wakes via `github`.
