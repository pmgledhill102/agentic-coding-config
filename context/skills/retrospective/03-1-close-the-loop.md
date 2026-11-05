### 1. Close the loop (always first)

Start with `~/.claude/bin/agent-telemetry event retrospective start`; step 10's
run record is timed from it.

**Before reading anything, check the session can reach `paul-context` at all.** The closed-loop reads below, the journal entry in step 8, and every cross-repo Issue step 6 routes all target a repo that is *not* the one this session is working in — most often `pmgledhill102/paul-context`. A **repo-scoped session** — a cloud sandbox is one — can only reach the repos attached to it, and a GitHub call against an unattached repo is **refused outright**. This is a different failure from having no local clone: the API call itself is denied, and the denial arrives as a 403 or a 404 that reads like "no such Issues" rather than "no access", so it is easy to record as an empty history and move on.

Confirm the scope *here*, at the top, rather than at the point of the first write. A cheap read is enough: `mcp__github__get_file_contents` on `journal/` with `fields: ["name"]` either works or is denied, and its listing is the input to the history read below. Discovering the denial in step 8 means the whole session has been analysed with nowhere to put the output.

If the repo is out of scope, the remedy is to **attach it** (`add_repo`, on surfaces that have it). Who decides depends on the repo:

- **`pmgledhill102/paul-context` only:** if the scope probe (listing its `journal/` directory) is denied and `add_repo` is available, call `add_repo(owner: "pmgledhill102", repo: "paul-context", access: "push")`, re-run the probe, and say in one line that it was attached. Do not ask. Push access is needed because step 8 writes the journal entry there. A surface's own confirmation prompt on `add_repo` does not count as the skill asking.
- **Every other repo:** attaching is the user's call, not yours. Say which repo is missing and what it blocks, and ask. Do not attach repos unilaterally.
- **If `add_repo` is absent or the attach fails:** do not silently continue as though the history were empty. A retro that cannot reach `paul-context` can still analyse the session, but it must say up front that the journal entry and the cross-repo Issues have no destination.

With scope confirmed, read what the last few retros produced and what became of it:

- **Recent journal entries** — the last 3–5. From the scope probe's listing of `journal/`, take the newest filenames (they sort by their date prefix) and read each with `mcp__github__get_file_contents` (else `gh api repos/pmgledhill102/paul-context/contents/journal/<file>`). No checkout is needed on any surface. Then list **open** `journal-draft` Issues on `pmgledhill102/paul-context` (`mcp__github__list_issues` with `labels: ["journal-draft"]` and `fields`): only fallback entries from step 8 and older drafts not yet drained live there, so fold in any that are newer than the files. This lookup is **read-only and best-effort**: missing it costs a little history, never a lost entry.
- **Retro-filed Issues** — their bodies carry the `From retro: paul-context/journal/...` backlink. Check the repos the recent journals routed to, listing both open and closed Issues. These are historical, so body-text search is acceptable here (the never-search rule guards *time-sensitive* reads; a week-old issue is safely indexed).

Report a short fate summary before proposing anything new:

- **Accepted** — merged or closed-completed. Did they pay off? Say so where the evidence exists ("the allow rule from #241 fired this session"), and say "no evidence yet" where it doesn't.
- **Rejected** — closed not-planned, or open and untouched across several sessions.
- **Pending** — filed recently, no verdict yet.

**A persistently rejected category is closed, twice over.** Stop proposing it — and record the category itself as a subtraction candidate for step 4, because the skill text or apparatus that keeps generating it is what should go.
