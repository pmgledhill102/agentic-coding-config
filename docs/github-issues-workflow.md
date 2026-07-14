# GitHub Issues workflow

How work is tracked in personal repos, replacing beads
(see [ADR-0013](../adrs/0013-github-issues-for-work-tracking.md)).

## Structure

| Concept | Mechanism | Notes |
| --- | --- | --- |
| Epic → Feature → Task | Sub-issues (`--parent`) | Nests up to 8 levels; 100 children per parent |
| Type | Labels `type: epic\|feature\|task\|bug` | Issue *types* are org-only; labels work everywhere |
| Priority | Labels `P0`–`P4` | P0 critical … P2 medium … P4 backlog (beads scale) |
| Dependencies | Native blocked-by (`--blocked-by`) | Max 50 per relationship type; blocked icon in lists |
| History | Issue timeline | Automatic; includes label/state/relationship events |

## Everyday commands

```bash
# Epic
gh issue create --title "Epic: overhaul auth" --label "type: epic,P1" --body "..."

# Feature under the epic (issue 12), task under the feature (issue 15)
gh issue create --title "Feature: passkey login" --parent 12 --label "type: feature,P2" --body "..."
gh issue create --title "Add WebAuthn ceremony" --parent 15 --label "type: task,P2" --body "..."

# Dependencies
gh issue create --title "Wire session storage" --blocked-by 14 --body "..."
gh issue edit 17 --add-blocked-by 16

# Ready work: open and not directly blocked
gh issue list --search "is:open -is:blocked" --json number,title,labels

# My active work
gh issue list --assignee @me --state open
```

Prefer the GitHub MCP tools (`issue_write`, `sub_issue_write`,
`issue_read`, `list_issues`) when the MCP server is connected; the `gh`
commands above are the fallback and the cloud-sandbox option.

## Rules for agents

- **Never use the search API for anything time-sensitive.** `gh search
  issues` and `/search/issues` are eventually consistent — a
  just-created issue can be invisible for seconds to minutes. Use
  `gh issue list` or direct reads (`gh issue view <n>`), which are
  strongly consistent. Deduplicate against `gh issue list --state all`,
  not search.
- **Create an issue before starting work** (same habit as `bd create`),
  and close it when the work merges: `gh issue close <n> --comment
  "Shipped in #<pr>"`. Reference the issue from the PR body (`Closes
  #<n>`) so closure is automatic on merge.
- **"Ready" is approximate.** `-is:blocked` filters direct blocks only;
  there is no transitive ready-work query. For a solo backlog this is
  fine — check the blocked icon before claiming work.
- **Keep issues small and specific.** Agent-dispatch data
  (dotnet/runtime, 878 PRs) shows 1–50-line changes succeed at 76–80%
  vs 64% at 100+ lines. State expected vs actual behaviour and
  acceptance criteria in the body — the issue is the prompt.
- **Batch politely.** When creating many issues in a loop, pace writes
  (~2 s apart). Secondary rate limits allow at most 80 content-creating
  requests/min, and bursts trigger 403s.

## Label bootstrap

New repos need the label set once (idempotent):

```bash
for l in "P0:b60205" "P1:d93f0b" "P2:fbca04" "P3:0e8a16" "P4:c5def5"; do
  gh label create "${l%%:*}" --color "${l##*:}" --force
done
for t in epic feature task bug; do
  gh label create "type: $t" --color 1d76db --force
done
```

`/setup-repo` is the natural home for this — tracked in
[#49](https://github.com/pmgledhill102/agentic-coding-config/issues/49)
follow-ups.
