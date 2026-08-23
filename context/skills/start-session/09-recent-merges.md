### 5. Recent merges to `<default>` (Tier 1 — surface)

From gather section `recent_main_commits`. The first line is `count=<N>` — commits that merged into `origin/<default>` since the previous local tip (i.e. the activity the user missed since they last opened this repo). When non-zero, subsequent lines are `<short-sha> <subject>` (capped at 10, oldest-first; topmost line is the most recent).

- **`count=0`**: silent. Caught up.
- **`count >= 1`**: surface a `Recent merges:` block in the session brief listing the entries verbatim. Useful before picking up new work — orients the user on what landed while they were away.

This is informational only — no action prompts. The section adds a few lines on busy days and zero on quiet ones.
