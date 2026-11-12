# Cloud sandbox

True only in an **ephemeral cloud sandbox**; the durable-machine fragment is
never composed into one — see ADR-0018 principle 5 and ADR-0020.

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
- **Docker** builds here go through the egress proxy: read `sandbox-docker` first.
- **A blocked host is not a dead end.** Ask for it: the proxy takes the new
  domain within seconds, though `WebFetch` may keep refusing until the session
  resumes, so retry with `curl` first. Re-test recorded blocks; they age badly.
- **`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` may be the literal `proxy-injected`**:
  the proxy cannot SigV4-sign, so check the key's shape before diagnosing IAM.

## `gh` is a property of the setup line

GitHub work prefers the MCP tools. Otherwise `gh api repos/{owner}/{repo}/...` (REST) works for reads and most writes
on repos attached with `add_repo`, but `actions/variables`, `actions/secrets` and `DELETE git/refs` are refused, and
GraphQL-backed subcommands (`gh issue list`, `gh pr list`, `gh pr view`, search), `/user/*` and `/orgs/*` are blocked.
Verify, never assume. Two answers here are confidently wrong: **every GitHub request carries credentials, even a bare
`curl`**, so a 200 says nothing about visibility (read `.private`); and **`git push --delete` prints "Everything
up-to-date" and deletes nothing** (check `git ls-remote --heads`). Helpers that shell out to `gh` report
`gh-unavailable` or `gh-unauthorized`: say what could not be gathered rather than reporting a clean result, and treat
a `gh` command written into a skill as naming the *operation*, then reach for the MCP call. `claude-code-remote` works
here; judge it by what a call returns, not by what kind of session you think you are. On an approval-binding failure
(anthropics/claude-code#90127, reported for child sessions), fall back to event-driven wakes via `github`.
