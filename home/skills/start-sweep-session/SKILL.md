---
name: start-sweep-session
description: 'Open a session aimed at backlog volume rather than depth: chain start-session, triage the open issues for small unambiguous fixes, group them into shared-concern bundles, and work the bundles in parallel — one branch and one PR each. Use when the goal is to get the open-issue count down, when asked to clear low-hanging fruit or quick wins, or when the backlog has grown too crowded to see the complex work inside it.'
---

# Start a sweep session

A normal session picks one issue and goes deep. This one goes wide: it finds the
issues that are cheap and unambiguous, works several at once, and leaves the
backlog shorter.

The problem it exists for is not that hard issues are hard. It is that small
ones crowd them out. Each small fix costs a whole session cycle — start, sync,
triage, branch, PR, watch checks — so none is ever worth picking on its own, and
together they bury the items that actually need thought. A sweep pays that
overhead once and spreads it across a bundle.

Which means this skill optimises for **count**, and count is the wrong objective
for anything that needs a decision. That is not a flaw to work around; it is the
boundary. Everything below exists to keep work that needs judgment out of the
sweep, and the honest outcome when nothing qualifies is to say so and stop.

## Action tiers

The same three tiers as `start-session`, and for the same reason — a sweep does
more per confirmation than an ordinary session, so the tiering has to be at
least as strict, never looser.

- **Tier 1 — auto-act, no prompt**: reading issues, reading the working tree,
  verifying a defect is still present, composing the plan.
- **Tier 2 — auto-act behind one batched confirmation**: cutting branches,
  creating worktrees, pushing, opening PRs. One confirmation covers the whole
  sweep plan, and it is taken **before the first branch is cut**, not per bundle.
- **Tier 3 — surface only, user drives**: anything an issue leaves open, any
  candidate that fails the eligibility bar, and any bundle that stops mid-flight.

When in doubt, downgrade a tier. Never upgrade silently.

## Phase 1 — Start the session

Invoke `/start-session` and carry its brief forward. Do not reimplement any of
it: the sync, the issue listing, the container-currency check and the brief are
that skill's contract, and duplicating them here would give the sweep a second
source of truth to drift from.

Three of its outcomes decide whether a sweep may proceed at all:

- **`state=failed` from the bootstrap-currency check** — stop. A container
  missing an unknown subset of its toolkit cannot be trusted to report what its
  gates did, and a sweep multiplies that by the number of bundles. Report and
  hand back.
- **An unclean working tree** — ask before proceeding. Worktrees branch from
  `origin/<default>` and are unaffected by it, so this is not a technical
  blocker; it is a signal that the session already has work in flight, and a
  sweep on top of that is rarely what was wanted.
- **A branch assigned to this session by the harness** — a sweep needs one
  branch per bundle, so it cannot honour a single assigned branch. Name this in
  the confirmation step and get explicit permission for the extra branches.
  Never create them on the assumption that the assignment was a formality.

## Phase 2 — Triage (Tier 1)

### 2a. Shortlist cheaply

Start from the open-issue list `start-session` already fetched. Rank it by the
signals that cost nothing to read:

- **Prefer** `type: task` and `type: bug`, and the lower priorities — P3 and P4
  are where small self-contained work accumulates, because nothing forced it to
  be picked.
- **Deprioritise** `type: epic` and `type: feature`. A feature is occasionally
  sweepable; an epic never is.
- **Prefer a title that names its own fix.** Titles in this estate are written
  as findings ("X is cited in three places and does not exist"), so a title that
  already contains the correction is strong evidence the body will too.

Take a shortlist of roughly 20–30, not the whole backlog.

### 2b. Read the shortlist

Now fetch bodies — `start-session` deliberately omits them, and the sweep cannot
judge eligibility without them. Prefer `mcp__github__list_issues` with `body` in
`fields` over one `issue_read` per issue; fall back to `gh issue view` where the
MCP server is unavailable. Bodies are the expensive part of this skill, which is
why the shortlist comes first.

### 2c. Apply the eligibility bar

All six must hold. A candidate that fails any one of them is deferred with a
one-line reason, never quietly dropped:

1. **The change is named, not designed.** The issue says what to do, or the fix
   is obvious from reading the code it names. If the first step is deciding what
   "right" looks like, it is not fruit.
2. **Small blast radius.** A handful of files, no interface everything else
   depends on, no decision that belongs in an ADR.
3. **Verifiable here.** The repo's own gates can show the fix is right, on this
   surface, without a credential or a toolchain this session lacks.
4. **No unanswered questions.** At most one, and only where it has an obvious
   default you would state rather than ask.
5. **Still live.** Verified in Phase 2d, below — against the working tree, not
   against the issue text.
6. **Unclaimed.** No open PR and no branch already addressing it. A sibling
   session's branch is invisible from here
   ([#436](https://github.com/pmgledhill102/agentic-coding-config/issues/436)),
   so check the remote branch list as well as open PRs, and treat a near-miss
   branch name as claimed.

### 2d. Verify each candidate is still real

For every surviving candidate, open the file it names and confirm the defect is
still there. This is the step it is tempting to skip, and the one with a
documented failure behind it: three of five issues `start-session` offered as
ready work had already been fixed
([#416](https://github.com/pmgledhill102/agentic-coding-config/issues/416)).

An already-fixed candidate is not a wasted read — it is the cheapest yield the
sweep has. Collect these separately and propose closing them with a comment
naming the commit or PR that fixed them. Closing five stale issues costs no
branches, no CI and no review, and it reduces the count exactly as much as
fixing five.

## Phase 3 — Bundling (Tier 1)

A **bundle** is 2–5 eligible issues that share a concern — the same file, the
same fragment, the same helper script, or one rule that has to be restated in
several places. An issue that shares a concern with nothing else becomes a
**singleton bundle**, which is perfectly normal and still earns its own branch.

Shared concern is what keeps the single-concern PR rule honest. One PR closing
four issues is fine when the four are one change seen from four angles; the same
PR closing four unrelated fixes is the thing that rule exists to prevent.

Two invariants make the parallelism safe, and both are hard:

- **No file may appear in two bundles.** Two worktrees editing one file produce
  two PRs that conflict on merge, and the conflict surfaces after review rather
  than before. Where two issues need the same file, they go in the same bundle
  or one of them waits for the next sweep.
- **At most one bundle per sweep may touch generated artefacts.** In this repo
  that means `context/`: a change there is regenerated with
  `python3 tests/compose-context.py --write`, whose outputs are shared files
  that every other `context/` change also rewrites. One bundle owns them, or
  every bundle collides in the same place.

Cap the sweep at **3 bundles by default, 5 at the most.** The binding constraint
is review, not execution — a sweep that opens eight PRs has moved the queue
rather than shortened it. Carry the rest to the next sweep; it will be cheaper
now that they are already triaged.

## Phase 4 — The sweep plan (Tier 2 — one confirmation)

Print the plan and take one confirmation for the whole of it:

```text
── Sweep plan ─────────────────────────────────
Backlog: <N> open

Close now (already fixed, no branch needed):
  #<n>  <title>        — fixed by <sha|PR>

Bundle A — <shared concern>            branch: sweep/<slug>
  #<n>  <title>
  #<n>  <title>
  files: <path>, <path>

Bundle B — <shared concern>            branch: sweep/<slug>
  …

Deferred (<M>):
  #<n>  <one-line reason>              — needs a decision / blocked / claimed

Effect if all land: <N> → <N-k> open
[This session was assigned branch <x>; the sweep needs <k> branches — ok?]
───────────────────────────────────────────────
Proceed? (y/n)
```

A "no" is a complete answer. The triage above is the expensive part and it is
now done; ending here with a shortlist the user can pick from by hand is a
useful session, not a failed one.

## Phase 5 — Work the bundles in parallel (Tier 2 — covered by Phase 4)

One worktree per bundle, each branched from the up-to-date default branch so no
bundle inherits another's changes:

```sh
git worktree add ../sweep-<slug> -b sweep/<slug> origin/<default>
```

Follow the repo's own branch-naming convention where it has one; `sweep/<slug>`
is the fallback.

Then one agent per bundle, run concurrently, each given:

- the issue numbers, titles and bodies in its bundle;
- **the file list it owns** — and the rule that it may not touch anything
  outside that list;
- its worktree path, and the instruction to work only inside it;
- the repo's quality gates, to run before reporting done;
- the stop rule below.

**The stop rule.** If the fix turns out to need a judgment call, the agent stops
that bundle, leaves the worktree as it is, and reports what the question is. It
does not decide. Eligibility asserted there were no unanswered questions, so
finding one falsifies the premise the bundle was built on — and guessing turns a
cheap fix into a wrong one that takes a full review cycle to discover. The same
applies when a fix turns out to need a file another bundle owns.

A defect noticed in passing is a new issue, filed, not folded into the bundle.
Widening a bundle mid-flight is how a sweep turns into the deep session it was
supposed to avoid.

**Where parallelism is unavailable** — no worktree support, or a surface that
cannot run concurrent agents — run the bundles one at a time on branches cut the
same way, with the same contract. Parallelism is an accelerator here, not the
mechanism; the bundling is what does the work.

## Phase 6 — Land each bundle

In each worktree, in this order:

1. **Run the repo's gates** — whatever its own instructions name, not a fixed
   list carried in this skill. Push only on a clean run.
2. **Commit** with a message that says what changed and why, several short
   paragraphs rather than one long line.
3. **Push** with `git push -u origin sweep/<slug>`.
4. **Open one PR per bundle**, with a `Closes #<n>` line for every issue it
   fixes and a short paragraph per issue saying what the fix was. Never close an
   issue by hand: the trailer is the audit trail, and merge commits — the only
   merge method enabled in this estate — preserve it.
5. **Remove the worktree** once the push succeeds (`git worktree remove`). The
   branch is on the remote; the local worktree is scaffolding.

Do not merge, and do not approve. A sweep produces reviewable PRs; it does not
land them.

## Phase 7 — Sweep report

```text
── Sweep result ───────────────────────────────
Opened:
  PR #<n>  <title>              closes #<a>, #<b>
  PR #<n>  <title>              closes #<c>

Closed without a PR (already fixed):
  #<n>, #<n>, #<n>

Stopped mid-bundle:
  Bundle C — <the question that stopped it>

Deferred, with reasons:      <M> issues
Backlog: <N> → <N-k> open, <k> more pending review
───────────────────────────────────────────────
```

The deferred list is the part worth reading. After a sweep, what remains should
be the work that genuinely needs thought — which was the point of clearing the
rest out of the way.

## Guardrails

- **Never sweep across repos.** A session edits the repo it is working in.
  Anything spotted elsewhere is filed as an issue there, not fixed here.
- **Never split two issues that touch one file across two bundles.** That
  invariant is what makes the parallel worktrees safe; without it the sweep
  manufactures merge conflicts.
- **Never guess at a fix.** The eligibility bar is no unanswered questions.
  Discovering one is a stop and a report, not a judgment call to make quietly.
- **Never widen a bundle mid-flight.** File the new finding as its own issue.
- **Never close an issue by hand.** `Closes #<n>` in the PR body, so the close
  is tied to the change that earned it.
- **Never merge or approve your own PRs.**
- **Never exceed the bundle cap** because the backlog is long. A long backlog is
  the reason for the next sweep, not for a bigger one.
- **Never proceed on a failed bootstrap.** Parallel work in a container that
  cannot report its own state produces several unverifiable PRs instead of one.
