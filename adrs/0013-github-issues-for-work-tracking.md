# ADR-0013: GitHub Issues replaces beads for work tracking

- **Status**: Accepted (2026-07-14)
- **Date**: 2026-07-14
- **Tags**: workflow, tooling, issue-tracking

## Context

Beads (`bd`) has been the issue tracker across repos since January 2026.
It works, but its weight is disproportionate for solo hobby projects:
a ~45 MB binary, an embedded Dolt database per repo, schema migrations
that require a "designated migrator" machine, git hooks that conflict
with the pre-commit framework (the `bd-push-safe` shim exists solely to
work around this), and sync failures that block work — during the
research session itself, `bd create` refused to run pending four
unreconciled schema migrations. Beads' sweet spot is fleets of parallel
agents (Gas Town); ours is one human plus one agent.

Research (2026-07-13, tracked in issue
[#49](https://github.com/pmgledhill102/agentic-coding-config/issues/49))
compared GitHub Issues, Backlog.md, Linear, beads_rust, and git-bug
against the actual requirements: repo-scoped tracking with history,
Epic→Feature→Task hierarchy, dependencies, priorities, multi-machine
sync, and agent ergonomics. Key findings:

- GitHub shipped the previously missing pieces: sub-issues (GA Apr 2025,
  8 levels deep), native blocked-by/blocking dependencies (GA Aug 2025),
  and first-class `gh` CLI flags for both (v2.94.0, Jun 2026). All were
  verified working on this personal account's repos.
- The rumoured responsiveness problems do not bite a solo dev with one
  agent. Measured API latency is 0.26–0.57 s per call; rate limits only
  affect bulk migrations and tight polling loops. The one real hazard is
  the eventually consistent **search** API — mitigated by using
  strongly consistent direct reads (`gh issue list`, `GET` by number).
- The industry converged on issue trackers as the agent task queue:
  issues are now assignable to Copilot, Claude, and Codex on github.com,
  so this choice compounds rather than dead-ends.
- Claude Code has no built-in persistent tracker; its documented pattern
  is an external tracker via MCP — which is already connected.

## Decision

Adopt GitHub Issues as the work tracker for all personal repos,
replacing beads. Conventions live in
[docs/github-issues-workflow.md](../docs/github-issues-workflow.md);
per-repo migration follows
[docs/beads-migration-runbook.md](../docs/beads-migration-runbook.md)
using the deterministic `home/bin/bd-migrate-to-github` script.

Summary of the conventions:

- Hierarchy via **sub-issues**: epic → feature → task.
- Priority via labels **P0–P4** (issue types and Priority fields are
  org-only; labels are the personal-account mechanism).
- Type via labels (`type: epic|feature|task|bug`).
- Dependencies via native **blocked-by** relationships.
- Agents use `gh issue list` / direct reads, never `gh search issues`,
  for anything time-sensitive.

## Consequences

- The beads integration in this repo (bd `prime` hooks, `bd-*` commands,
  `bd-push-safe`, permission allowlist entries, `.beads/` workspaces)
  retires once migration is proven — tracked as follow-up work under
  issue #49, deliberately separate from this decision.
- Work tracking now requires network access. Accepted: offline operation
  was explicitly not a requirement.
- Ticket data lives in GitHub rather than in-repo. History is preserved
  via the issue timeline (stronger than beads' history) but is no longer
  cloned with the repo.
- `bd remember` memories are not carried to GitHub Issues; the migration
  script exports them to a markdown file for manual triage into
  CLAUDE.md or auto-memory.
