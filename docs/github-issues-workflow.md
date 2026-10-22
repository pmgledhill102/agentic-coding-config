# GitHub Issues workflow

How work is tracked in personal repos. The decision and the history behind it
are in [ADR-0013](../adrs/0013-github-issues-for-work-tracking.md); this file
states the current conventions only.

## Structure

| Concept | Mechanism | Notes |
| --- | --- | --- |
| Epic → Feature → Task | Sub-issues (`--parent`) | Nests up to 8 levels; 100 children per parent |
| Type | Labels `type: epic\|feature\|task\|bug` | Issue *types* are org-only; labels work everywhere |
| Priority | Labels `P0`–`P4` | P0 critical … P2 medium … P4 lowest priority, but intended |
| Dependencies | Native blocked-by (`--blocked-by`) | Max 50 per relationship type; blocked icon in lists |
| History | Issue timeline | Automatic; includes label/state/relationship events |

## Ideas are not issues

**An issue means "I will do this".** It reads as a commitment and counts
toward the backlog, and every triage session re-reads it. An idea (a design, a
capability, a "worth doing one day") is a file instead. `P4` is the lowest
priority of work that is intended; an idea-shaped item never gets an issue at
`P4` or at any other priority.

- **Location:** a top-level `ideas/` directory, the same name in every repo.
  Create it when the first idea lands, never in advance.
- **Home rule:** an idea lives in the repo that would implement it. One that
  spans repos, or has no home yet, goes in `paul-context/ideas/`.
- **Shape:** one idea per file, `ideas/<slug>.md`, beginning:

  ```markdown
  # <title>

  Status: parked (YYYY-MM-DD)
  Trigger: <the concrete event that would make this work>
  From: <owner/repo#n, if it was an issue>
  ```

  Then the original issue body, carried over unchanged so no reasoning is
  lost. Comments stay reachable through the `From:` link.
- **A trigger is required.** "A second project needs model access" is one;
  "when it becomes a problem" is not.
- **Promotion:** when the trigger fires, open an issue that links the file and
  set `Status: promoted → #<n>`. The file stays as the record.
- **Parking an existing issue:** move the body into the file, then close the
  issue as not planned with "Parked as an idea: `ideas/<slug>.md`". The
  `bundle-issues` skill does this in bulk with its `PARK` verdict.

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
- **Create an issue before starting work**, and close it when the work
  merges: `gh issue close <n> --comment
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

## Security-control defects

This repo is public, and so is its tracker. One class of finding does not
belong in it. The general rule, for every public artefact including commit
messages and PR bodies, is
[ADR-0022](../adrs/0022-public-artefact-content.md); this section is how it
applies to filing an issue here.

- **Security-control defects go to `paul-context`.** A finding that a
  credential guard, `PreToolUse` hook, allowlist/deny rule or secret-handling
  path does not do what it claims is filed as an issue on
  `pmgledhill102/paul-context`, not here. Filed here it is a precise, indexed,
  public description of a control that does not fire, with no embargo and no
  fix date.
- **This repo still gets the fix**, with a title describing the change rather
  than the hole. The rule covers the *report*, not the code: the fix, its test
  and its rationale are public as usual. What stays private is the window
  between knowing and fixing.
- **A vulnerability report is evidence**, and evidence is private under
  ADR-0022.
- **Scope: controls that are supposed to stop something.** An ordinary bug in
  a security-adjacent tool — a wrong exit code or a misleading message from
  `gcp-credentials`, say — is not in scope and is filed here as usual.
  Over-applying this moves half the tracker into a private repo and loses the
  public record that makes this one useful.
- **Refer to private work by description, not by `repo#number`**, per
  ADR-0022.

This rule governs new findings. It does not migrate issues already filed here;
those are triaged separately.

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

`/setup-repo` applies this as one of its steps, so a repo set up through it
already has the labels; the loop above is for anything that was not.

**Label-less infra repos**: a secondary repo that will never get the
full `/setup-repo` baseline (a Terraform-only sibling, a mirror) ends up
with GitHub's default labels, so cross-repo Issues filed against it
can't use the convention above — `--label "type: task,P2"` just fails.
Run `/setup-repo --labels-only` there: it applies step 7 alone,
including the established-taxonomy guard, and skips branch protection
and repo settings.
