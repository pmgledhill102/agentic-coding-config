## Action tiers

Every step in Phase 1 falls into one of three tiers — keep this in mind when adding or editing steps:

- **Tier 1 — auto-act, no prompt**: safe, reversible, expected. Examples: `git fetch --prune`, `git pull --rebase`, read-only surface listings.
- **Tier 2 — auto-act behind one batched confirmation**: destructive but predictable, judgment is yes/no for the whole list. Examples: deleting merged branches, deleting squash-merged branches, pushing `main` if ahead.
- **Tier 3 — surface only, user drives**: needs per-item judgment, or affects shared state in ways one y/n can't capture. Examples: open PRs awaiting merge, open issues still assigned to you, stashes, user-started background processes.

When in doubt, downgrade a tier (Tier 1 → 2, or 2 → 3). Never upgrade silently.
