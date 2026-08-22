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

Ready to pick up next:
  #<n>  P<pri>  <title>            (top 5 by priority; or "none — backlog empty")
  …

Needs attention:
  • <pending journal drafts: N>    (omit when 0 / not paul-context)
  • <feature branch behind main by N>          (omit when on default, even, or auto-switched)
  • <branch upstream gone but tree dirty>      (omit unless that case fires)
  • ~/.claude is behind the repo on N file(s): <paths> — run `chezmoi apply --refresh-externals`
                                               (omit when behind=0 / skipped)
  • ~/.claude has N hand-edited file(s): <paths> — the edits are lost on the next
    apply; move them into the repo    (omit when modified=0 / skipped)
───────────────────────────────────────────────
```

Rules:

- Sections with nothing to say collapse to a single `none` line; "Needs attention" is omitted entirely when empty.
- "Ready to pick up next" is sourced from gather section `gh_ready`. Each row is already pipe-separated `#<n>|P<pri>|<title>` — split on `|`, sort by priority label (P0 first, `-` last), and emit the top 5. Ready = open and not directly blocked; the filter is direct-blocks-only, so eyeball the blocked icon before claiming work.
- "In progress" is sourced from gather section `gh_assigned`. Same `#<n>|P<pri>|<title>` row shape; no cap (usually 0–3 items).
- "Recent merges" is sourced from gather section `recent_main_commits`. Omit the entire section when `count=0`.
- If the repo has no GitHub origin (`gh_ready` / `gh_assigned` report `not-github` or are skipped), drop both issue sections silently (the brief still shows git lines).
- A section the gather could not answer says `n/a (gh absent)` rather than `none`. An unchecked list must never read as "all clear".
- Truncate any title to ~78 columns to keep rows on one line.
