### 8. Open PRs needing your action (Tier 3 — surface only)

From the `list_pull_requests` response gathered in step 1(b). Remember it has
no author filter, so on a shared repo it lists everyone's open PRs — say so
rather than implying they are all yours. On a personal repo the two are the
same set.

Categorise and present:

- **Mergeable, CI green, approved/no-review-needed** → "ready to merge in UI"
- **Mergeable, CI green, awaiting review** → "waiting on reviewer"
- **CI failed** → list with link to the failing run
- **Merge conflict** → list with PR URL
- **Draft** → list separately

Never auto-merge. List, link, move on.
