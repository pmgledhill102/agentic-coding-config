### 7. Session brief (Tier 1 — final summary)

Always print, even when everything is clean. This is the user-facing payoff — one screenful, scannable, no surprises. Format:

```text
── Session brief ──────────────────────────────
Repo:     <repo>             Branch: <branch> (<clean|dirty>)
Sync:     <default> <ahead/behind/even>   upstream <ahead/behind/even/gone/n/a>
          [auto-switched <feature> → <default> (upstream gone)]    (only when Step 3 auto-switched)

Recent merges:                                      (omit when count=0)
  <short-sha>  <commit subject>
  …                                                 (cap at gather's 10)

In progress (assigned to you):
  #<n>  P<pri>  <title>            (or "none")

Open issues (blocked filter unavailable):
  #<n>  P<pri>  <title>            (top 5 by priority; or "none — backlog empty")
  …

Needs attention:
  • <pending journal drafts: N>    (omit when 0 / not paul-context)
  • <feature branch behind main by N>          (omit when on default, even, or auto-switched)
  • <branch upstream gone but tree dirty>      (omit unless that case fires)
  • <unpushed commits: N — this container is disposable>   (omit when 0)
  • container config is behind <installed> → <head> — re-run the bootstrap: <remedy>
                                               (omit unless state=behind)
───────────────────────────────────────────────
```

Rules:

- Sections with nothing to say collapse to a single `none` line; "Needs attention" is omitted entirely when empty.
- The issue list is titled **"Open issues (blocked filter unavailable)"**, not "Ready to pick up next". That is not a cosmetic difference: the query in step 1(b) cannot express `-is:blocked`, so some rows may be blocked. Titling it as a ready list would assert a filter that was never applied. Sort by priority label (P0 first, `-` last), emit the top 5, and check an issue's blockers before claiming it.
- "In progress" is the same response filtered client-side to the authenticated login. Report the real answer — including `none` when the filter genuinely returned nothing. It reads `n/a (no GitHub route)` **only** when the MCP call itself failed.
- "Recent merges" is sourced from gather section `recent_main_commits`. Omit the entire section when `count=0`.
- If the repo has no GitHub origin, drop both issue sections silently (the brief still shows git lines).
- Unpushed commits earn a line here that they would not earn on a durable machine: the container is reclaimed after a period of inactivity, and unpushed work goes with it.
- Truncate any title to ~78 columns to keep rows on one line.
