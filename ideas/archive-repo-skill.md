# New skill proposal: /archive-repo — archive a repo without stranding PRs or waking Dependabot

Status: parked (2026-11-14)
Trigger: The next time a repo is due to be archived
From: pmgledhill102/agentic-coding-config#126

From retro: paul-context/journal/2026-07-30-gcp-org-management-automate-migration-closeout.md

Proposal for a new skill: **`/archive-repo`** — archive a GitHub repo the clean way, encoding the ordering and gotchas learned archiving `automate-github`, `automate-trains` and `automate-gym` (2026-07-30).

One-line description: correct the README against the code, drain open PRs/issues, then archive — in an order that doesn't strand anything or wake Dependabot.

The sequence a naive "archive it" misses, all hit in one session:

1. **Merge or close every open PR first** — archiving freezes PRs open *forever* (they can't be merged or closed on an archived repo). We archived with 12 open Dependabot PRs across two repos and had to unarchive to fix it.
2. **Unarchiving wakes Dependabot immediately** — it opened 6 fresh PRs within a minute of the unarchive. The fix loop is: unarchive → close PRs + delete branches → re-archive *fast*. Better: never enter the loop.
3. **Correct the README before archiving, against the code, not the old docs** — archiving preserves whatever the README claims permanently (see automate-inbox#27: `automate-trains`' README misdescribed its own API usage and the false claim propagated into wrongly-named secrets in two GCP projects). Record known defects fixed only in a successor so the archive isn't read as correct.
4. **Close open issues with a routing comment** (superseded-by pointer, or "refile against <successor>").
5. **Add an archive banner**: successor link, verification date, "nothing here executes any more", and mark all config/setup docs as historical.
6. Archive (`gh repo archive` — the GitHub MCP has no archive tool), then verify: `isArchived: true`, 0 open PRs, 0 open issues.

Pre-flight checks the skill should encode: list open PRs/issues before anything; confirm any local working copy is on synced main; if the repo is a superseded one, require the successor link up front.

Acceptance criteria:

- New command file in `home/commands/` following existing conventions
- Encodes the ordering above with the merge-before-archive and Dependabot gotchas as hard steps, not notes
- Tier model: archival itself confirmed with the user; PR-closing presented as one batched y/n
