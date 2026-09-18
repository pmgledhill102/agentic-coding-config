---
name: start-sweep-session
description: 'Open a session aimed at backlog volume rather than depth: pick up Bundle Issues that /bundle-issues has already triaged, re-verify them, and work them in parallel — one branch and one PR each. Use when the goal is to get the open-issue count down, when asked to clear low-hanging fruit or quick wins, or when start-session reports ready bundles.'
---

# Start a sweep session

A normal session picks one issue and goes deep. This one goes wide: it takes
work that has already been triaged, does several bundles at once, and leaves the
backlog shorter.

It does **not** triage. That job belongs to `/bundle-issues`, which spends a
whole session's context reading every open body and writes its conclusions into
Bundle Issues. This skill consumes them.

Keeping those apart is deliberate. Triage wants maximum context and execution
wants none, and a session trying to do both has to shortlist — which is a guess
dressed as a filter. It also means there is exactly **one** triage
implementation. Two that can disagree is the drift problem this estate is
otherwise strict about.

## Action tiers

- **Tier 1 — auto-act**: reading bundles, re-verifying them, composing the plan.
- **Tier 2 — one batched confirmation**: cutting branches, creating worktrees,
  pushing, opening PRs. One confirmation covers the whole plan, taken **before
  the first branch is cut**.
- **Tier 3 — surface only**: anything a bundle leaves open, and any bundle that
  stops mid-flight.

When in doubt, downgrade a tier. Never upgrade silently.

## Phase 1 — Start the session

Invoke `/start-session` and carry its brief forward. Do not reimplement it.

Two of its outcomes decide whether a sweep may proceed:

- **`state=failed` from the bootstrap-currency check** — stop. A container
  missing an unknown subset of its toolkit cannot be trusted to report what its
  gates did, and a sweep multiplies that by the number of bundles.
- **A branch assigned to this session by the harness** — a sweep needs one
  branch per bundle, so it cannot honour a single assigned branch. Name this at
  the confirmation step and get explicit permission. Never create the extra
  branches on the assumption that the assignment was a formality.

An unclean working tree is not a blocker here: worktrees branch from
`origin/<default>` and are unaffected by it. Mention it and carry on.

## Phase 2 — Pick up the bundles (Tier 1)

`/start-session`'s brief carries a `Ready bundles:` block, sourced from open
issues whose title starts with `Bundle:`. Use it. If the brief showed none:

> No ready bundles. Run `/bundle-issues` to triage the backlog first? (y/n)

On yes, chain into it and come back. On no, stop — there is nothing here to
sweep, and inventing a shortlist is the thing this split exists to remove.

Read the chosen Bundle Issues in full. Each carries the issues it covers, the
files involved, the verification SHA, the gates and the stop rule.

**Check the selected bundles are disjoint before going further.** `/bundle-issues`
guarantees that within one run; two bundles from different runs carry no such
promise. If two selected bundles name the same source file, drop one from this
sweep and say so.

Take at most **3 bundles** by default, 5 at the most. The binding constraint is
review load, not execution — a sweep that opens eight PRs has moved the queue
rather than shortened it.

## Phase 3 — Re-verify, and do not skip this (Tier 1)

A bundle asserts its issues were live **at the SHA in its body**, and says
nothing about now. Between then and this session, someone may have fixed one, a
sibling session may have claimed another, or the file may have moved.

For each issue in each selected bundle, confirm the defect is still present —
the same targeted search `/bundle-issues` used, against the current tree. This
is cheap: a handful of files per bundle. It is the whole reason the expensive
read can be done once and reused.

- **Still live** → keep it in the bundle.
- **Already fixed** → drop it from the bundle and close it, noting what fixed it.
- **Now claimed** (an open PR or a branch references it) → drop it.
- **Nothing left in the bundle** → close the Bundle Issue as done and move on.

## Phase 4 — The sweep plan (Tier 2 — one confirmation)

```text
── Sweep plan ─────────────────────────────────
Bundle #<n> — <concern>                branch: sweep/<slug>
  #<n>  <title>
  #<n>  <title>
  files: <path>, <path>

Bundle #<n> — <concern>                branch: sweep/<slug>
  …

Dropped on re-verification:
  #<n>  already fixed — closing
  #<n>  now claimed by PR #<n>

Effect if all land: <N> → <N-k> open
[This session was assigned branch <x>; the sweep needs <k> branches — ok?]
───────────────────────────────────────────────
Proceed? (y/n)
```

A "no" is a complete answer, and cheaper than it used to be: the bundles keep,
and the re-verification just told you which of them decayed.

## Phase 5 — Work the bundles in parallel (Tier 2 — covered by Phase 4)

One worktree per bundle, each branched from the up-to-date default branch so no
bundle inherits another's changes:

```sh
git worktree add ../sweep-<slug> -b sweep/<slug> origin/<default>
```

Follow the repo's own branch-naming convention where it has one; `sweep/<slug>`
is the fallback.

Then one agent per bundle, run concurrently, each given the Bundle Issue's
contents, its worktree path, the file list it owns — and the rule that it may
not touch anything outside that list — plus the gates and the stop rule.

**The stop rule.** If a fix turns out to need a judgment call, the agent stops
that bundle, leaves the worktree, and reports the question. It does not decide.
Eligibility asserted there were no unanswered questions, so finding one
falsifies the premise the bundle was built on, and guessing turns a cheap fix
into a wrong one that costs a review cycle to discover. The same applies when a
fix needs a file another bundle owns.

A defect noticed in passing is a new issue, filed, not folded in. Widening a
bundle mid-flight is how a sweep becomes the deep session it was meant to avoid.

**Where parallelism is unavailable** — no worktree support, or a surface that
cannot run concurrent agents — run the bundles one at a time on branches cut the
same way, with the same contract. Parallelism is an accelerator; the bundling is
what does the work.

## Phase 6 — Land each bundle

In each worktree, in this order:

1. **Run the repo's gates** — whatever its own instructions name, not a fixed
   list carried in this skill. Push only on a clean run.
2. **Regenerate anything generated**, with the repo's tooling and never by hand.
   In this repo that is `python3 tests/compose-context.py --write`, and the
   regenerated outputs are committed with the change.
3. **Commit** with a message saying what changed and why, several short
   paragraphs rather than one long line.
4. **Push** with `git push -u origin sweep/<slug>`.
5. **Open one PR per bundle**, with a `Closes #<n>` line for every issue it
   fixes and a short paragraph per issue. Never close an issue by hand: the
   trailer is the audit trail, and merge commits — the only merge method enabled
   in this estate — preserve it. Reference the Bundle Issue, and close it too
   once its last issue is covered.
6. **Remove the worktree** once the push succeeds (`git worktree remove`).

Do not merge, and do not approve.

### When a generated file conflicts

Expected, and not a problem to design around. Two bundles editing different
fragments both regenerate the same composed outputs, so whichever lands second
may conflict or go stale.

**Resolve it by merging the base branch and re-running the generator. Never by
editing a generated file.** The generator is the arbiter; there is nothing to
adjudicate. The repo's composition check is the backstop that makes a wrong
merge impossible to land quietly, so a red check here is information, not
damage.

This is why the bundling invariant is about **source** files only. Treating
generated outputs as authored ones would serialise most of this repo's sweepable
work to prevent a failure that is cheap, loud and mechanically fixable.

## Phase 7 — Sweep report

```text
── Sweep result ───────────────────────────────
Opened:
  PR #<n>  <title>              closes #<a>, #<b>
  PR #<n>  <title>              closes #<c>

Closed without a PR (fixed since triage):
  #<n>, #<n>

Stopped mid-bundle:
  Bundle #<n> — <the question that stopped it>

Bundles remaining:           <r>
Backlog: <N> → <N-k> open, <k> more pending review
───────────────────────────────────────────────
```

## Guardrails

- **Never triage here.** No bundles means run `/bundle-issues`, not improvise a
  shortlist.
- **Never work a bundle without re-verifying it.** It was true at a SHA, not
  now.
- **Never sweep across repos.** A session works the repo it is in.
- **Never put two bundles on the same source file** — and never extend that to
  generated files, which have a mechanical resolution.
- **Never hand-edit a generated file to resolve a conflict.** Re-run the
  generator.
- **Never guess at a fix.** Discovering an open question is a stop and a report.
- **Never widen a bundle mid-flight.** File the new finding as its own issue.
- **Never close an issue by hand.** `Closes #<n>` in the PR body.
- **Never merge or approve your own PRs.**
- **Never proceed on a failed bootstrap.**
