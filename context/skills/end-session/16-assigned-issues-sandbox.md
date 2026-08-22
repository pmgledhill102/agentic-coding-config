### 10. Open issues assigned to you (Tier 3 — surface)

From the `list_issues` response gathered in step 1(b), filtered client-side to issues whose `assignees` include the authenticated login. Surface count + numbers/titles. User decides which to close — common forgetfulness pattern.

Report the real answer, including `none` when the filter genuinely returned nothing. This line reads `n/a (no GitHub route)` **only** when the MCP call itself failed — an unchecked list must never read as "nothing assigned".

Issues whose work merged this session via a `Closes #<n>` reference in the PR body are closed automatically by GitHub on merge, so they won't appear here. Anything listed is genuinely still outstanding — if a listed issue actually shipped without the `Closes #<n>` trailer, suggest closing it with `mcp__github__add_issue_comment` followed by `mcp__github__issue_write` (method `update`, `state: "closed"`, `state_reason: "completed"`).
