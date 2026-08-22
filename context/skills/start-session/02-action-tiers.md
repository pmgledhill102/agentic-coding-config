## Action tiers

Every step falls into one of three tiers — keep this in mind when adding or editing steps:

- **Tier 1 — auto-act, no prompt**: safe, reversible, expected. Examples: `git fetch --prune`, `git pull --rebase` on the default branch, read-only surface listings.
- **Tier 2 — auto-act behind one batched confirmation**: predictable but should be a conscious choice. Example: chaining into `/promote-journal-inbox` when journal drafts are pending.
- **Tier 3 — surface only, user drives**: needs per-item judgment. Examples: a feature branch trailing `main`, issues left assigned mid-flight from the last session, red `main` CI.

When in doubt, downgrade a tier (Tier 1 → 2, or 2 → 3). Never upgrade silently.
