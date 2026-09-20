# Cloud sandbox

True only in an ephemeral cloud sandbox; the workstation fragment is never
composed into one — see ADR-0018 principle 5.

## This container is the whole environment

There is no chezmoi here, and `~/.claude/` is not chezmoi-managed.
`cloud/bootstrap.sh` writes most of it at build time, but the platform
launcher writes there too and refreshes its files each session, so presence
says nothing about age or owner — `~/.agents/.bootstrap-manifest` lists ours.

Anything installed by hand dies with the container and is invisible to the
next session. What must survive belongs in the repo or the setup script.

## Capabilities available here

- **Brokered Google Cloud access**, when `CREDENTIAL_BROKER_URL` is set.
  Request it with the `gcp-credentials` skill rather than asking a human to
  run `gcloud` by hand. The trigger is not "I need to change something in
  GCP" but **"I am about to assert something about live GCP state"**.
- **Skills delivered by the bootstrap** are the whole set — absent here means
  held back deliberately, not lost. Say so rather than improvising.
- **A blocked host is not a dead end.** Ask for it: the proxy takes the new
  domain within seconds, though `WebFetch` may keep refusing until the session
  resumes, so retry with `curl` first. Re-test recorded blocks; they age badly.

## `gh` is a property of the setup line

GitHub work goes through the MCP tools. `gh` is present only when the setup
line passes `--with-gh`, and GraphQL is blocked for every Claude Code session
whatever the binary's state, so `gh pr view`, `gh pr list` and review-thread
commands fail; REST reads have been seen to work. Verify, never assume. Helpers
that shell out to `gh` report `gh-unavailable` or `gh-unauthorized`: say what
could not be gathered rather than reporting a clean result, and treat a `gh`
command written into a skill as naming the *operation* — reach for the MCP
call. `claude-code-remote` works here: `list_triggers`, `send_later` and `delete_trigger` all
succeeded on 2026-09-20. Judge it by what a call returns, not by what kind of session you think you are — on an approval-binding failure (anthropics/claude-code#90127, reported for child sessions), fall back to event-driven wakes via `github`.
