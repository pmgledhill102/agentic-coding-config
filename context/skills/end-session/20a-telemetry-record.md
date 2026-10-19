### 15a. Telemetry record (Tier 1 — local append, then a metadata-only send)

After the summary is printed, once, whatever the outcome — including a red PR or
an unpushed branch. A session that ended badly is the one most worth recording.

```sh
~/.claude/bin/agent-telemetry session-end repo=<owner/repo> branch=<branch> issues=<n,n> prs=<n,n>
```

- **`repo`, `branch`**: the repo and branch this run worked on. Leave a pair out
  rather than guessing it.
- **`issues`, `prs`**: the numbers this session touched, comma-separated and
  digits only, qualified by repo in `repo` when more than one repo was involved.
  Omit the pair when there were none.
- **Nothing else.** The helper takes only the keys it allowlists and drops the
  rest, so free text — a title, a comment, an error message — cannot ride along,
  and none should be offered. Duration, the cache verdict and degraded
  capabilities are read from the session marker and the bootstrap manifest by
  the helper itself; do not compute or pass them.

It appends one `session` record to the local spool and then ships whatever is
unsent. With no ingest configured it only spools, and says nothing.

**Never let this be the reason end-session stops or reports a problem.** If the
helper is absent (an older bootstrap, a machine it was never installed on),
skip silently. If it prints a line, do not relay it. It exits 0 on every runtime
failure by design.
