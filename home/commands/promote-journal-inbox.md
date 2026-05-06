Drain the journal-draft inbox for `paul-context`: move filesystem drafts from `~/dev/paul-context/_incoming/` to `journal/`, drain GitHub Issues labeled `journal-draft` from `pmgledhill102/paul-context` into `journal/`, commit each, push once, then close the drained Issues with back-links. Run from `~/dev/paul-context/` (the slash command lives in `agentic-coding-config` per the slash-commands-in-dotfiles convention; the work happens in `paul-context`).

See `paul-context/decisions/2026-05-05-journal-inbox-promotion.md` for the design rationale.

## Pre-flight

This command **must run inside the `paul-context` working tree.** It commits to that repo; running elsewhere would write into the wrong place. Run the bare commands below and branch on their exit codes — don't paste compound `||` / `&&` forms, which won't match any single allow rule.

```sh
git rev-parse --is-inside-work-tree
basename "$(git rev-parse --show-toplevel)"
```

If the first command's exit code is non-zero (or stdout is not `true`), abort with `/promote-journal-inbox requires a git-backed repo, stopping.` and stop.

If `basename` doesn't match `paul-context`, abort with `/promote-journal-inbox must run from ~/dev/paul-context/, not <where>` and stop.

If the working tree is dirty (`git status --porcelain` non-empty), surface the dirty paths and ask the user to commit/stash before promotion. Don't bundle unrelated changes into journal commits.

## Phase 1 — Filesystem inbox drain

### 1. Enumerate `_incoming/`

```sh
ls _incoming/ 2>/dev/null
```

Filter to filenames matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md$` and exclude `README.md` (tracked separately). Capture the matching list.

If empty, surface `(no filesystem drafts pending)` and skip to Phase 2.

### 2. For each draft, in deterministic order

For each `<filename>` in the sorted list:

1. **Conflict check**: if `journal/<filename>` already exists, skip. Append to the conflict-list as `<filename> — already in journal/, left in _incoming/`. Continue with the next draft.
2. `git mv _incoming/<filename> journal/<filename>` — preserves the filename exactly.
3. Stage with `git add journal/<filename>` (already staged by `git mv`, but explicit is safer for the followup commit).
4. Derive the commit message slug: strip the leading `<YYYY-MM-DD>-` from `<filename>` and the trailing `.md`. The remainder is `<source-repo-slug>-<topic-slug>`.
5. Commit each draft separately:

   ```sh
   git commit -m "journal: <YYYY-MM-DD> <source-repo-slug>-<topic-slug>"
   ```

   Per-draft commits keep the audit trail clean and let any single entry be reverted without touching others.

## Phase 2 — Issue inbox drain

### 1. Find labeled Issues

```sh
gh issue list --repo pmgledhill102/paul-context \
    --label journal-draft --state open --limit 100 \
    --json number,title,body,createdAt
```

If the `gh` CLI is unavailable, fall back to `mcp__github__list_issues` with `labels=["journal-draft"]` and `state=OPEN`.

If empty, skip to Phase 3.

### 2. For each Issue

For each Issue, in `createdAt` order (oldest first):

1. **Strip prefix**: the title shape is `journal: <YYYY-MM-DD>-<source-repo-slug>-<topic-slug>` (no `.md`). Strip the literal `journal:` prefix (with trailing space). The remainder + `.md` is `<filename>`.
2. **Validate filename**: must match `^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md$`. If not, skip with `Issue #N — title doesn't match journal-draft shape, left open` in the conflict-list. Don't try to coerce.
3. **Conflict check**: if `journal/<filename>` already exists, skip with `Issue #N — journal/<filename> already exists, left open` in the conflict-list. Don't close.
4. **Write body**: write the Issue body **verbatim** to `journal/<filename>`. The body IS the journal markdown — no transformation, no front-matter strip. Use the `Write` tool.
5. **Stage**: `git add journal/<filename>`.
6. **Commit**: `git commit -m "journal: <YYYY-MM-DD> <source-repo-slug>-<topic-slug>"` — date from `<filename>` (already correct), slug from filename per Phase 1.
7. **Capture** Issue `#N` for the close step in Phase 4.

Don't close any Issues yet. Closing happens **after** the push so a failed push doesn't strand drained drafts.

## Phase 3 — Push

If nothing was committed (Phase 1 + Phase 2 both produced zero new commits):

- Surface `(nothing to push)` and skip to Phase 4.

Otherwise:

```sh
git push origin main
```

If push fails (rejected, network, hook):

- Surface the error verbatim.
- **Do not** close any Issues. Drafts stay committed locally; the next run will see `journal/<filename>` already exists for those entries and skip them as conflicts (until the user manually resolves by `git push`-ing). The Issues remain open as the source of truth.
- Stop. Don't proceed to Phase 4's close step.

If push succeeds, proceed to Phase 4.

## Phase 4 — Close drained Issues

For each Issue captured in Phase 2:

1. Add a back-link comment via `mcp__github__add_issue_comment`:

   ```text
   Promoted to paul-context/journal/<filename> (commit <short-sha>). Closing.
   ```

   (Capture the commit sha from `git rev-parse HEAD~<N+offset>` or by walking the recent log — straightforward when each draft is its own commit.)

2. Close the Issue via `mcp__github__issue_write` with `method=update`, `state=closed`, `state_reason=completed`.

If a comment or close fails, surface the failure and continue with the rest. The bead has already been promoted (the journal entry is live on `main`), so a missed close is a recoverable bookkeeping issue — re-running `/promote-journal-inbox` will re-enumerate the still-open Issues, find the journal entries already exist, surface them as conflicts, and the user can close manually.

## Phase 5 — Summary

Print a tight wrap-up:

```text
/promote-journal-inbox complete.

  Filesystem drafts drained: <N>
  Issue drafts drained:      <N>
  Conflicts (skipped):       <N>
<for each conflict>:
    - <filename or Issue ref> — <reason>

  Pushed: <yes/no/n/a>
  Closed Issues: <count> — <list of #N or "(none)">
```

Surface the conflict list explicitly so it's obvious what didn't move and why.

## Guardrails

- **Never overwrite** an existing `journal/<file>.md`. Skip + surface. Manual resolution lives with the user.
- **Per-draft commits**, single batched push. Each entry is its own commit — clean audit trail, easy revert. The single push at end keeps remote round-trips down and makes the close-Issues precondition simple.
- **Close-Issues happens AFTER push.** If push fails, drafts stay committed locally but upstream Issues remain open — the next run handles the recovery cleanly via the conflict path.
- **No retries on network failures.** Surface and stop. The user drives the retry.
- **No body transformation on Issue drafts.** What the Issue body says is what lands in `journal/`. Don't try to fix typos, normalise headings, or strip metadata — that's manual editing, not promotion.
- **Don't `cd` away from `paul-context`** during the run. Every git operation should target the same working tree the pre-flight validated.
