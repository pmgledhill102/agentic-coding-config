### 8. Execute

**Order matters**: write the journal **first** so subsequent issues can reference its path. Then create everything else. The one exception is an approved fix (item 3): derive the journal's filename, make the fix, then file the journal, so the journal can name the commit and the fix's PR can cite the journal's path.

1. **journal** (first, after any approved fix):
   - **Derive the filename.** `<source-repo-slug>` = sanitised basename of `git remote get-url origin` from the current cwd (lowercase, `[a-z0-9-]+`). If no git remote, use `basename "$PWD"`. `<topic-slug>` = kebab-cased session summary, ≤5 words. `<filename>` = `<YYYY-MM-DD>-<source-repo-slug>-<topic-slug>.md`.
   - **Resolve same-project same-day collisions** at write-time: if an open Issue with the same title already exists, append `-2`, `-3`, … before `.md` until unique. Rare in practice — same project, same day, same topic — but the suffix prevents silent merge of two distinct retros.
   - **Stage the draft first, always.** `Write` the journal markdown to `/tmp/<filename>`. `Edit(/tmp/**)` is auto-allowed on every surface (and `Edit` rules cover the `Write` tool), so this write always succeeds and the draft exists on disk before any network call. Nothing below can lose it.
   - **Then file it as an Issue — on every surface, with no branch.** Create the issue on `pmgledhill102/paul-context` with the `journal-draft` and `P4` labels and the title `journal: <filename-without-.md>`, body taken from the staged file. Prefer `mcp__github__issue_write`; the `gh` form is the portable fallback:

     ```sh
     gh issue create --repo pmgledhill102/paul-context \
         --label journal-draft --label P4 \
         --title "journal: <filename-without-.md>" \
         --body-file /tmp/<filename>
     ```

     The `journal-draft` label and the `journal:` (with trailing space) title prefix are how `/promote-journal-inbox` finds the draft. Promotion infers the eventual filename by stripping `journal:` (with trailing space) from the Issue title and appending `.md`, so the filename is stable from draft → committed.

     **`P4` is load-bearing, not decoration — don't drop it as noise.** `estate-report` counts an issue with no `P0`–`P4` label as untriaged and flags a repo above five of them, so unlabelled drafts accumulate into a flag that points at the journal inbox rather than at any real triage debt. A priority keeps them out of that count. `P4` is also the honest reading: a draft awaiting a mechanical move is the lowest-urgency thing in the repo.

     **Never copy the draft into a local `_incoming/` instead.** That route used to be preferred and was the worse of the two: `_incoming/*` is gitignored, so a copy there cannot be committed and dies with the container — during `end-session`, exactly when the container is about to be walked away from. An Issue is durable the instant it is created, and is the same route on every surface.
   - **If the Issue create fails** (offline, no GitHub route): print the full draft to the session log with clear `===BEGIN JOURNAL===` / `===END JOURNAL===` delimiters and tell the user to save it manually. The staged `/tmp` copy also still exists. Don't silently discard content.
   - Capture `paul-context/journal/<filename>` (the eventual post-promotion path) for cross-references in subsequent issues.
2. **durable lesson**: execute whatever route step 6 named for this surface. Step 6 is where that decision lives; do not restate or second-guess it here.
3. **fix** (same-repo, approved in step 7): the one place the retro changes repo state, and only for rows the user confirmed.
   - **Find a live home first, by a fresh read.** Check the session's PR is still open **now** (`mcp__github__pull_request_read` method `get`, else `gh pr view`) — not from anything read earlier in the session. The user often merges while the session runs, and a merged PR's branch is usually deleted. Open → commit on that branch and push. Merged, closed, or no PR → a new branch from the up-to-date default branch and a small PR of its own, titled for what it fixes.
   - The PR body carries the "why" an issue would have, plus `From retro: paul-context/journal/<file>.md`. Do not merge it.
   - Capture the commit SHA and the PR number for the summary. The journal names those, not an issue number.
4. **issue** (same-repo): create it against the current repo, with a `type:` label and a `P<n>` priority — `mcp__github__issue_write`, else `gh issue create --title="..." --body-file=... --label "type: <type>,P<n>"` from the **current cwd**. Body **MUST** include `From retro: paul-context/journal/<file>.md` near the top, and the proposal's lever and tier price — the closed loop in step 1 reads these back later. Capture the issue number for the summary.
5. **issue** (cross-repo): create it against `pmgledhill102/<repo>`, naming the repo explicitly — `mcp__github__issue_write` with `owner`/`repo`, else `gh issue create --repo pmgledhill102/<repo>`. Filed from wherever the retro runs; never `cd` into the target repo (see 6a). Body **MUST** include `From retro: paul-context/journal/<file>.md`, plus lever and tier price. Capture the URL.
6. **settings**: file it as an Issue against `pmgledhill102/agentic-coding-config`, by either route — exactly as for any other cross-repo finding. Include the precise rule string, the friction it removes, and whether the command is read-only. **Do not apply the change to any `settings.json`** (see 6b); a single-line permission addition is still an Issue, not an edit.

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
- Fixed in place: <what> — `<sha>` on PR #<n> (and why, in a clause)
- Memory: `<slug>.md` — <one-line summary> (omit where step 6 named no memory route)

## Observations
- <findings that couldn't state all four proposal criteria, durable lessons
  with no memory route to land in, and anything else worth remembering>

## Phrasing
- "<what the owner said>" → <accurate term>: <the distinction it carries>.
  Cost: <extra step / clarifying question / wrong first guess / none, but a
  person might not have inferred it>
```

Tight is good — aim for 30-50 lines. Skip sections that are empty (don't write `## Costs this session\n(none)`, just omit).

#### 8b. Phrasing

Feedback to the owner on their own wording, so it sharpens for rooms where nobody quietly translates. **At most 3 items**, and the bar is strict: a real term misapplied ("CI" for a deploy, "merge" for "rebase"), or an instruction whose ambiguity cost an extra step — a question, a wrong first guess, extra reads to resolve it. No style notes, no typos, no shorthand that was perfectly clear. An empty section is the expected result; omit it from the journal when empty.

**Phrasing items are not proposals.** They take none of the 3-proposal cap and never go through step 5. This is not a dimension to scan for (see "Shape of this retro"): note an item only when the session actually paid for it.
