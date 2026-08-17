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
- **Tears down the beads pre-commit hook**: after verification passes it
  strips the beads hook from `.pre-commit-config.yaml` (see
  [Pre-commit hook teardown](#pre-commit-hook-teardown)).

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

## Sequencing: disable bd before or after migrating?

**After — with one exception.** The migration needs bd alive (`bd export
--all` reads the local database), and most per-repo integration is
gated on `.beads/metadata.json`, so it disables itself when `.beads/`
is removed in the post-migration checklist. Disabling first would break
the export and leave the repo with no tracker at all.

Per repo, the order is:

1. **Freeze bd writes first (the only "before" step).** Stop creating
   beads issues in the repo, so the export snapshot cannot go stale
   between export and cutover — anything created after the export is
   stranded. Take the export at migration time, not days ahead.
2. **Migrate** (procedure below).
3. **Run the post-migration checklist in the same session** — not as a
   lazy follow-up. `bd prime` output instructs every session to use
   beads for all tracking, which contradicts the new workflow the
   moment migration completes; deleting `.beads/` and stripping the
   CLAUDE.md/AGENTS.md blocks closes that conflict window.

**Global config is retired last, not first.** The `bd prime` hooks,
`bd-*` commands, `bd-push-safe`, and the `bd`/`beads`/`dolt` permission
entries in `home/settings.json` are shared by every repo — they must
survive until the final repo migrates, and they are inert in migrated
repos once the sentinel is gone. One final PR removes the lot (see
"Global cleanup" below).

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

## Pre-commit hook teardown

A migrated repo that keeps its beads pre-commit hook is a trap that
springs somewhere other than where you set it. With `bd` still on PATH
and `.beads/` gone the hook exits 0 — a silent no-op on the machine
that ran the migration. On a fresh clone, a second machine, or CI,
`bd` is absent, the hook fails, and **every commit is blocked**. Since
these hooks are written `always_run: true` / `pass_filenames: false`,
it fires on every commit regardless of what changed.

So after verification passes, `--apply` strips the beads hook from
`.pre-commit-config.yaml`:

- Hooks are matched on **what they run** — an `entry:` invoking `bd`,
  or any line referencing `.beads` — not on `id:`, which is
  inconsistent in the wild (`beads`, `beads-sync` and `bd-sync` have
  all been observed).
- If that empties a `- repo:` block, the whole block goes too;
  pre-commit refuses to parse a `hooks:` list with no entries.
- Editing is line-based, so every surviving line (comments, ordering,
  quoting) is byte-identical. Re-running is a no-op.
- If the config contains *nothing but* beads hooks, it is left alone
  with a warning — an empty `repos:` list does not parse, so that one
  needs a human to delete the file.

For a repo migrated before the script did this, run the teardown on its
own — it is guarded, skipping any repo that still has a live `.beads/`
directory:

```bash
~/.claude/bin/bd-migrate-to-github --strip-precommit-hook-only          # dry run
~/.claude/bin/bd-migrate-to-github --strip-precommit-hook-only --apply
```

Verify with `bd` off PATH, which is the condition that actually breaks:

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin pre-commit run --all-files
```

## Post-migration checklist (per repo)

1. Triage `.beads/memories-export.md` into the repo's CLAUDE.md or
   auto-memory, then delete it.
2. Remove the beads workspace: `rm -rf .beads/` (keep
   `migration-export.jsonl` and the state file somewhere first if
   you want an audit copy — e.g. attach them to the migration PR).
   The `.pre-commit-config.yaml` entry is already gone — the script
   removes it. If `bd hooks install` was ever run here, also
   `bd hooks uninstall` **before** deleting `.beads/`, while `bd` still
   works: those shims live in `.git/hooks/`, which is not version
   controlled, so they only affect this checkout (and no clone
   inherits them).
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

Mostly done. Removed from `home/` on 2026-07-18
([#123](https://github.com/pmgledhill102/agentic-coding-config/issues/123)):
the `bd prime` hooks, the `bd-*` commands, `bd-push-safe`, and the
`bd`/`beads`/`dolt` permission allowlist entries. `/start-session`,
`/end-session`, `/retrospective` and `/repo-review` now target GitHub
Issues and no longer mention beads at all. The retired paths are listed in
`home/retired-paths`, so machines that already had them lose them on the
next apply
([#125](https://github.com/pmgledhill102/agentic-coding-config/issues/125),
verified 2026-08-16).

What remains is `home/bin/bd-migrate-to-github` — the tool this runbook
drives. It retires with the last repo still on beads, along with that
repo's `.beads/` workspace, tracked under
[#131](https://github.com/pmgledhill102/agentic-coding-config/issues/131).
This runbook retires with it.
