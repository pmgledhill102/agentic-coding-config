### 1. Close the loop (always first)

**Before reading anything, check the session can reach `paul-context` at all.** The closed-loop reads below, the journal draft in step 8, and every cross-repo Issue step 6 routes all target a repo that is *not* the one this session is working in — most often `pmgledhill102/paul-context`. A **repo-scoped session** — a cloud sandbox is one — can only reach the repos attached to it, and a GitHub call against an unattached repo is **refused outright**. This is a different failure from having no local clone: the API call itself is denied, and the denial arrives as a 403 or a 404 that reads like "no such Issues" rather than "no access", so it is easy to record as an empty history and move on.

Confirm the scope *here*, at the top, rather than at the point of the first write. A cheap read is enough — listing that repo's Issues either works or is denied. Discovering the denial in step 8 means the whole session has been analysed with nowhere to put the output.

If the repo is out of scope, the remedy is to **attach it** (`add_repo`, on surfaces that have it) — and **that is the user's call, not yours**. Say which repo is missing and what it blocks, and ask. Do not attach repos unilaterally, and do not silently continue as though the history were empty: a retro that cannot reach `paul-context` can still analyse the session, but it must say up front that the journal draft and the cross-repo Issues have no destination.

With scope confirmed, read what the last few retros produced and what became of it:

- **Recent journal entries** — the last 3–5. List recent `journal-draft`-labeled Issues on `pmgledhill102/paul-context` (`mcp__github__list_issues` when connected, else `gh issue list --repo pmgledhill102/paul-context --label journal-draft --state all`), which covers everything not yet promoted. If a `paul-context` checkout happens to be at hand — you are standing in it, or it sits beside the current repo — also read its `journal/` (newest by filename date) for the promoted ones. This lookup is **read-only and best-effort**: missing it costs a little history, never a lost draft, which is why it carries none of the care that resolving a *write* destination used to need.
- **Retro-filed Issues** — their bodies carry the `From retro: paul-context/journal/...` backlink. Check the repos the recent journals routed to, listing both open and closed Issues. These are historical, so body-text search is acceptable here (the never-search rule guards *time-sensitive* reads; a week-old issue is safely indexed).

Report a short fate summary before proposing anything new:

- **Accepted** — merged or closed-completed. Did they pay off? Say so where the evidence exists ("the allow rule from #241 fired this session"), and say "no evidence yet" where it doesn't.
- **Rejected** — closed not-planned, or open and untouched across several sessions.
- **Pending** — filed recently, no verdict yet.

**A persistently rejected category is closed, twice over.** Stop proposing it — and record the category itself as a subtraction candidate for step 4, because the skill text or apparatus that keeps generating it is what should go.
