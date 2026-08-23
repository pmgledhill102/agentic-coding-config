### 8. Execute

**Order matters**: write the journal **first** so subsequent issues can reference its path. Then create everything else.

1. **journal** (always first):
   - **Derive the filename.** `<source-repo-slug>` = sanitised basename of `git remote get-url origin` from the current cwd (lowercase, `[a-z0-9-]+`). If no git remote, use `basename "$PWD"`. `<topic-slug>` = kebab-cased session summary, ≤5 words. `<filename>` = `<YYYY-MM-DD>-<source-repo-slug>-<topic-slug>.md`.
   - **Resolve same-project same-day collisions** at write-time: if the target already exists, append `-2`, `-3`, … before `.md` until unique. Filesystem path checks `~/dev/paul-context/_incoming/<filename>`; Issue path checks for an open Issue with the same title (rare in practice — same project, same day, same topic — but the suffix prevents silent merge of two distinct retros).
   - **Pick the inbox path:**
     - **Filesystem inbox** (preferred): if `[ -d ~/dev/paul-context/_incoming ] && [ -w ~/dev/paul-context/_incoming ]`, `Write` the journal markdown to `~/dev/paul-context/_incoming/<filename>`. **No git operations against `paul-context`.**
     - **GitHub Issue fallback** (no reachable clone — the test above failed): stage the journal markdown with the `Write` tool to `/tmp/<filename>` (`Edit(/tmp/**)` is auto-allowed, and `Edit` rules cover the `Write` tool), then file as a labeled Issue:

       Create the issue on `pmgledhill102/paul-context` with the
       `journal-draft` label and the title `journal: <filename-without-.md>`,
       body taken from the staged file. Prefer `mcp__github__issue_write`;
       the `gh` form below is the portable fallback, and matters here because
       this path fires precisely when the session is in a sandbox:

       ```sh
       gh issue create --repo pmgledhill102/paul-context \
           --label journal-draft \
           --title "journal: <filename-without-.md>" \
           --body-file /tmp/<filename>
       ```

       The `journal-draft` label and the `journal:` (with trailing space) title prefix are how `/promote-journal-inbox` finds the draft. Promotion infers the eventual filename by stripping `journal:` (with trailing space) from the Issue title and appending `.md`, so the filename is stable from draft → committed.
     - **Both unreachable** (rare — offline AND no local clone): print the full draft to the session log with clear `===BEGIN JOURNAL===` / `===END JOURNAL===` delimiters and stop. Don't silently discard content. Tell the user to save it manually.
   - Capture `paul-context/journal/<filename>` (the eventual post-promotion path) for cross-references in subsequent issues. The path is stable across both inbox paths because both preserve `<filename>` exactly.
2. **durable lesson**: execute whatever route step 6 named for this surface. Step 6 is where that decision lives; do not restate or second-guess it here.
3. **issue** (same-repo): create it against the current repo, with a `type:` label and a `P<n>` priority — `mcp__github__issue_write`, else `gh issue create --title="..." --body-file=... --label "type: <type>,P<n>"` from the **current cwd**. Body **MUST** include `From retro: paul-context/journal/<file>.md` near the top, and the proposal's lever and tier price — the closed loop in step 1 reads these back later. Capture the issue number for the summary.
4. **issue** (cross-repo): create it against `pmgledhill102/<repo>`, naming the repo explicitly — `mcp__github__issue_write` with `owner`/`repo`, else `gh issue create --repo pmgledhill102/<repo>`. Filed from wherever the retro runs; never `cd` into the target repo (see 6a). Body **MUST** include `From retro: paul-context/journal/<file>.md`, plus lever and tier price. Capture the URL.
5. **settings**: file it as an Issue against `pmgledhill102/agentic-coding-config`, by either route — exactly as for any other cross-repo finding. Include the precise rule string, the friction it removes, and whether the command is read-only. **Do not apply the change to any `settings.json`** (see 6b); a single-line permission addition is still an Issue, not an edit.

If any single create fails, surface the error and continue with the rest. Don't roll back successful artifacts on partial failure.

#### 8a. Journal entry format

```markdown
# YYYY-MM-DD — <session summary>

**Project**: <repo or context>
**Duration**: <approximate>
**Issues created/closed this session**: <list, or "none">

## Closed loop
- <fate of prior retro output: accepted / rejected / paid off; categories retired>

## Costs this session
- <the ≤3 biggest costs and the lever pull for each — including ones that
  didn't clear the proposal bar>

## Created from this retro
- Issue: <repo> — <issue title> (<lever> / <tier price> / <priority> / <URL>)
- Memory: `<slug>.md` — <one-line summary> (omit where step 6 named no memory route)

## Observations
- <findings that couldn't state all four proposal criteria, durable lessons
  with no memory route to land in, and anything else worth remembering>
```

Tight is good — aim for 30-50 lines. Skip sections that are empty (don't write `## Costs this session\n(none)`, just omit).
