### 1. Close the loop (always first)

Before analysing this session, read what the last few retros produced and what became of it:

- **Recent journal entries** — the last 3–5. List recent `journal-draft`-labeled Issues on `pmgledhill102/paul-context` (`mcp__github__list_issues` when connected, else `gh issue list --repo pmgledhill102/paul-context --label journal-draft --state all`), which covers everything not yet promoted. If a `paul-context` checkout happens to be at hand — you are standing in it, or it sits beside the current repo — also read its `journal/` (newest by filename date) for the promoted ones. This lookup is **read-only and best-effort**: missing it costs a little history, never a lost draft, which is why it carries none of the care that resolving a *write* destination used to need.
- **Retro-filed Issues** — their bodies carry the `From retro: paul-context/journal/...` backlink. Check the repos the recent journals routed to, listing both open and closed Issues. These are historical, so body-text search is acceptable here (the never-search rule guards *time-sensitive* reads; a week-old issue is safely indexed).

Report a short fate summary before proposing anything new:

- **Accepted** — merged or closed-completed. Did they pay off? Say so where the evidence exists ("the allow rule from #241 fired this session"), and say "no evidence yet" where it doesn't.
- **Rejected** — closed not-planned, or open and untouched across several sessions.
- **Pending** — filed recently, no verdict yet.

**A persistently rejected category is closed, twice over.** Stop proposing it — and record the category itself as a subtraction candidate for step 4, because the skill text or apparatus that keeps generating it is what should go.
