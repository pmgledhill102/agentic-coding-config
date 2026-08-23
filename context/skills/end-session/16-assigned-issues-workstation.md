### 10. Open issues assigned to you (Tier 3 — surface)

From gather section `gh_assigned` (silently skipped when the repo has no github.com origin or `jq` is unavailable). Each line is `#<n> <title>` — an open GitHub issue assigned to you. Surface count + numbers/titles. User decides which to close — common forgetfulness pattern.

Issues whose work merged this session via a `Closes #<n>` reference in the PR body are closed automatically by GitHub on merge, so they won't appear here. Anything listed is genuinely still outstanding — if a listed issue actually shipped without the `Closes #<n>` trailer, suggest closing it: `gh issue close <n> --comment "Shipped in #<pr>"`, or the equivalent through a structured GitHub API tool where the client offers one.
