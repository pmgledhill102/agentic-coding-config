# Beads → GitHub Issues migration runbook

Per-repo procedure for migrating a beads (`bd`) database to GitHub
Issues using `home/bin/bd-migrate-to-github` (deployed to
`~/.claude/bin/` via chezmoi). One repo at a time; each repo is
independent.

## What the script guarantees

- **Deterministic**: issues are created in `(created_at, id)` order, so
  the same export always produces the same numbering.
- **Idempotent / resumable**: every completed step is recorded in
  `.beads/github-migration-state.json` immediately. Interrupt it, hit a
  rate limit, lose the network — re-running skips completed work and
  continues. It never re-creates an issue it has already created.
- **Rate-limit aware**: mutating calls are paced (default 2 s apart)
  and retried with exponential backoff + jitter, honouring
  `Retry-After` on 403/429/5xx.
- **Eventual-consistency aware**: it never touches the search API.
  Verification uses direct GETs by issue number (strongly consistent);
  linking freshly created issues retries briefly on 404.
- **Dry-run by default**: without `--apply` it prints the full plan and
  writes nothing.

What it migrates: title, description, notes, open/closed state,
priority (P0–P4 labels), type (`type: *` labels), a `beads-import`
label, hierarchy (`parent-child` → sub-issues), dependencies (`blocks`
→ blocked-by), supersedes edges (cross-reference comment), and a
provenance footer with the original bd id and timestamps. `bd remember`
memories are written to `.beads/memories-export.md` for manual triage —
they do not become issues.

What it does not migrate: comment threads (beads comments are rare in
these repos; check `comment_count` in the export before migrating a
repo where they matter), assignees, and in-progress status
(`in_progress` issues arrive as open — re-claim by assigning yourself).

## Procedure

```bash
cd <repo>

# 1. Preflight
gh auth status                      # authenticated, repo scope
bd export --all -o .beads/migration-export.jsonl   # works read-only even
                                    # when schema migrations block writes

# 2. Dry run — review the full plan
~/.claude/bin/bd-migrate-to-github --export .beads/migration-export.jsonl

# 3. Apply (paced; ~2s per write — a 40-issue repo takes ~3-4 minutes)
~/.claude/bin/bd-migrate-to-github --export .beads/migration-export.jsonl --apply

# 4. If it fails partway: fix the cause and re-run the same command.
#    The state file resumes exactly where it stopped.
```

The run ends with a verification pass (direct reads: state, labels,
sub-issue links, blocked-by links) and exits non-zero listing any
mismatches. Nothing is deleted on failure — re-run to converge.

## Post-migration checklist (per repo)

1. Triage `.beads/memories-export.md` into the repo's CLAUDE.md or
   auto-memory, then delete it.
2. Remove the beads workspace and its git hooks: `rm -rf .beads/`
   (keep `migration-export.jsonl` and the state file somewhere first if
   you want an audit copy — e.g. attach them to the migration PR).
3. Strip the `BEADS INTEGRATION` blocks from `CLAUDE.md` / `AGENTS.md`
   and replace with a pointer to
   [docs/github-issues-workflow.md](github-issues-workflow.md)
   conventions.
4. Spot-check in the UI: one epic shows its sub-issue tree; one blocked
   issue shows the blocked icon.

## Rollback

The beads database is untouched by migration (the script only reads the
export). Until `.beads/` is deleted in step 2 of the checklist, rolling
back means closing the created GitHub issues (they all carry the
`beads-import` label: `gh issue list --label beads-import`) and
carrying on with bd.

## Global cleanup (once all repos are migrated)

Tracked as follow-up work under
[#49](https://github.com/pmgledhill102/agentic-coding-config/issues/49):
retire the `bd prime` hooks, `bd-*` commands, `bd-push-safe`, and the
`bd`/`beads`/`dolt` permission allowlist entries from `home/`; update
`/start-session`, `/end-session`, `/retrospective`, and `/repo-review`
to target GitHub Issues.
