---
name: bundle-issues
description: 'Triage the whole open backlog in one dedicated session: read every open issue body, verify each against the working tree, close the ones already fixed, and emit the remainder as Bundle Issues that a later session can pick up with no prior context. Use when the backlog needs breaking down into workable units, when asked to plan a sweep or create bundles, or when the open-issue count needs bringing down.'
---

# Bundle the open issues

This session has one job: read the entire open backlog, decide what is
workable, and write that decision down somewhere durable. It does not fix
anything.

The split is the point. Triage wants **maximum** context — every open body at
once, because that is the only way to judge an issue on its evidence rather than
its title, and the only way to see that six issues share one cause. Execution
wants **none** — a session working one bundle should not be carrying eighty
issues it will never touch. Trying to do both in one session forces a shortlist,
and a shortlist is a guess dressed as a filter.

So: spend this session's context freely on reading, emit Bundle Issues, and let
a clean session do the work.

## Be austere about everything that is not reading

Every token spent elsewhere is a token not available for bodies, or for the
threads that correct them. Concretely:

- **Do not chain `/start-session`.** Its brief is exactly the summary this
  session does not need — it lists five issues when this one is about to read
  all of them.
- **Do not fetch CI status, PR lists or branch detail** beyond the claim check
  in step 5.
- **Do not read whole files to verify a claim** when a targeted search answers
  it. Most issues in this estate assert that a specific line says a specific
  wrong thing; confirming that is a grep, not a file read.

## Action tiers

- **Tier 1 — auto-act**: reading issues, verifying claims, writing the notes
  file.
- **Tier 2 — one batched confirmation**: closing the already-fixed issues, and
  creating the Bundle Issues. Both are taken together, once, at step 7.
- **Tier 3 — surface only**: anything that needs a decision, including every
  deferred issue and every cluster finding.

## 1. Minimal sync (Tier 1)

Verification compares issues against the working tree, so the tree has to be
current. Nothing more than this is needed:

```sh
git fetch --prune
git rev-parse --abbrev-ref HEAD
git status --porcelain
```

On the default branch and behind, `git pull --rebase --autostash`. On a feature
branch, say so and carry on — but record the SHA you actually verified against
in step 6, because that is what the bundles will claim.

Capture the verification SHA now:

```sh
git rev-parse --short HEAD
```

## 2. Fetch every open issue, with bodies (Tier 1)

Prefer `mcp__github__list_issues`; fall back to `gh issue list --json`.

```text
mcp__github__list_issues(owner, repo, state: "OPEN", perPage: 100,
                         fields: ["number", "title", "body", "labels", "assignees"])
```

Paginate until `hasNextPage` is false. `body` is what makes this session
expensive and what makes it worth running — do not drop it to save room.

**Ask for `comments` as well, and note what comes back: a per-issue count, not
the threads.** One extra field decides whether reading them is affordable rather
than guessing. Then read the threads on every issue that has any, if the total
is small enough not to crowd out the bodies — 44 open issues on `paul-context`
carried 36 comments between them and 27 had none, which is the usual shape.

This step used to say the opposite, and the reasoning is worth keeping because
it is half right: comments *are* where unanswered questions live, and an issue
with one defers anyway. The missing half is that they also hold **answers**,
which turn a `DEFER` into an `ELIGIBLE`, and **corrections**, which turn a body
into a description of a defect that has since moved. Neither is visible from the
body, by construction.

If the counts come back large enough to threaten the whole-backlog read, drop
this blanket fetch rather than the per-candidate read in step 5. That one is
never optional, and it is only ever a handful of issues.

## 3. Screen out claimed work (Tier 1)

One listing each, both filtered client-side:

```sh
git branch -r
```

```text
mcp__github__list_pull_requests(owner, repo, state: "open",
                                fields: ["number", "title", "head"])
```

An issue with an open PR, or with a branch whose name references it, is
**claimed** — a sibling session may be working it right now and its branch is
otherwise invisible from here. Claimed issues never enter a bundle.

## 4. Read and rule on each issue, writing as you go (Tier 1)

Work the list in number order and append one verdict per issue to a notes file
in the session scratch directory **as you go**. Do not hold the verdicts in your
head and synthesise at the end: by then this session is at its fullest, and the
bundling judgment is the part that most needs clear thinking. Notes on disk cost
nothing to re-read and do not degrade.

One line per issue:

```text
<number> | <verdict> | <concern-tag> | <files> | <one-line fix or reason>
```

Verdicts:

| Verdict | Means |
| --- | --- |
| `FIXED` | The defect is not in the tree any more. Step 7 closes it. |
| `ELIGIBLE` | Named fix, small blast radius, verifiable here, no unanswered questions, still live, unclaimed. |
| `DEFER` | Fails the bar. The reason goes in the last column, and it is always specific: "needs a decision about X", not "too big". |
| `CLAIMED` | An open PR or a branch already addresses it. |
| `BLOCKED` | A blocked-by dependency is still open. |

The bar for `ELIGIBLE` is **no unanswered questions, and an answer path that
exists**. An issue that asks the user something, or whose first step is deciding
what "right" means, is `DEFER` — however small the eventual edit turns out to be.

Two tests the bar as first written did not make:

- **Was the question already answered in the thread?** A body reading "needs a
  decision about X" defers only while X is open. Where a comment settles it, the
  issue is `ELIGIBLE` and the answer goes into the bundle, attributed to the
  comment so the working session can check it. This is the costly direction to
  get wrong: the deferred list is supposed to be the work that genuinely needs
  the user, so an issue deferred on a closed question corrupts the one output
  this session calls its real product.

  **This test needs step 2 to have read the threads**, and it is the only part
  of the comment handling that does. Step 5 cannot rescue it — an issue deferred
  here never reaches step 5. So when step 2 skipped the blanket fetch on volume,
  say so in the report: the deferred list is then "deferred on the body", which
  is a weaker claim than the one this skill usually makes for it.
- **Is the fix answerable, or only legible?** Where an item's fix names a tool,
  command, file or setting, confirm the repo names that thing somewhere. An item
  that requires inventing a contract the repo does not state is not eligible
  however clearly it is written. a-c-c#279 asked for a call to `list_triggers`
  "or the surface equivalent", which no surface in the estate names — it read as
  question-free, was bundled, and the working session correctly stopped.

## 5. Verify every candidate against the tree and its own comments (Tier 1)

For each issue not already `DEFER`ed, confirm the defect is still present. This
is the step with a documented failure behind it: three of five issues once
offered as ready work had already been fixed. Search for the specific claim:

```sh
grep -rn "<the string the issue says is wrong>" <path>
```

- Found → the issue stands.
- Not found → re-read before concluding. The wording may have changed while the
  defect remains. Only mark `FIXED` when the *defect* is gone, not when the
  quoted string has moved.

**Then read that issue's comments, every time.** Not the counts — the threads.
This is mandatory whatever step 2 decided about volume, because it is bounded by
the number of candidates rather than the size of the backlog, and because the
cost of skipping it is lopsided:

| A comment you miss on an issue that… | costs |
| --- | --- |
| defers | nothing — it was staying on the backlog either way |
| gets bundled or closed | a half-done fix, and the issue closed on it |

The second is a-c-c#425: a bundle enumerated the body's asks, a comment had
added a second clause to the same amendment, the PR shipped one of the two and
closed the issue. Caught a session later, by accident.

What to do with what you find:

- **A comment that adds to the ask** → fold it into that issue's line in the
  bundle, at the same specificity as the body's asks.
- **A comment that reverses or corrects the body** → surface it as its own line
  above the issue list. It must be impossible to miss, because the working
  session is about to act on a body that is wrong. `paul-context#68` is the
  worked specimen: one comment supplies the blocker the body leaves unnamed, a
  later one is titled "Correction to my comment above" and retracts it, and the
  body's headline evidence has been false for a month.
- **A comment that answers the body's open question** → the issue is eligible
  after all, per step 4. Say in the bundle where the answer came from.
- **A comment that opens a new question** → `DEFER`, whatever the body says.

## 6. Cluster, then bundle (Tier 1)

Re-read the notes file — not your memory of it — and work from there.

**First, look for clusters.** Several issues describing one underlying cause is
the finding this session exists to produce and no other session can: it is
invisible from a shortlist. Where you find one, say so in the report and propose
a single issue naming the cause, rather than bundling the symptoms.

**Then bundle.** A bundle is 2–5 `ELIGIBLE` issues that share a concern — the
same file, the same helper, the same rule restated in several places. An issue
sharing a concern with nothing else becomes a singleton bundle, which is normal.

Shared concern is what keeps one PR closing several issues honest against the
single-concern rule. Four issues that are one change seen from four angles: fine.
Four unrelated fixes: exactly what that rule exists to prevent.

**The invariant: no two bundles may touch the same source file — source, not
generated.** Two sessions
editing one file in two worktrees produce two PRs that conflict after review
rather than before. Where two issues need the same file, they go in one bundle
or one waits.

**Generated files are excluded from that invariant, deliberately.** In this repo
that means the composed outputs under `home/` and `profiles/`, which
`tests/compose-context.py --write` rewrites from `context/`. Two bundles editing
different fragments will both regenerate them, and that is fine: a conflict in a
generated file is resolved by a command rather than a judgment, and the
`composed context profiles` CI check makes a wrong merge impossible to land
quietly. Treating them as authored files serialises most of this repo's
sweepable work to prevent a failure that is cheap and loud.

Cap the bundles you emit at **5**, best-first. Unbundled `ELIGIBLE` issues are
reported, not lost; the next run is cheap now that they are triaged.

## 7. Confirm, then write (Tier 2 — one confirmation)

Print the plan and take one confirmation covering both the closes and the
Bundle Issues. Write it as markdown, not a fenced block: the chat surface wraps
at an unknown width, so column-aligned text loses its columns exactly where a
reader is deciding what to approve (the same defect as the retro's step 7 and
step 10 summaries). Tables and bullets survive wrapping; a label gutter does not.

> **Bundle plan** — read `<N>` open issues at `<sha>`
>
> **Close now (already fixed):** `<k>`
>
> - #`<n>` — `<title>`
>
> **Bundles to create:** `<b>`
>
> | Concern | Closes |
> | --- | --- |
> | `<concern>` | #`<n>`, #`<n>`, #`<n>` |
> | `<concern>` | #`<n>`, #`<n>` |
>
> **Clusters worth one issue instead:**
>
> - #`<n>`, #`<n>`, #`<n>` — `<the shared cause>`
>
> **Eligible but unbundled:** `<u>` · **Deferred:** `<d>`
>
> Create `<b>` Bundle Issues and close `<k>` fixed issues? (y/n)

On yes:

**Close the already-fixed issues**, each with a comment naming what fixed it.
These are the cheapest count reduction available — no branch, no CI, no review.

**Create one Issue per bundle**, titled `Bundle: <shared concern>`. One per
bundle, not one combined plan: each is then independently claimable, closeable
and assignable, and a clean session picks up exactly one.

The title prefix `Bundle:` is the contract that lets `/start-session` find these
with no setup in any repo. Do not reword it. Add a label too if the repo has a
suitable one, but never rely on the label alone.

Body:

```markdown
**Verified at:** `<sha>` on `<branch>`
**Concern:** <what these issues have in common>

## Issues

<Where a thread reverses or corrects an issue's body, say so here, above the
list, quoting the operative sentence. Do not leave it to be discovered.>

- [ ] #<n> — <what the fix is, specifically enough to be mechanical>
- [ ] #<n> — <…, including anything a comment added or settled, said as plainly
      as the body's own asks and attributed to the comment>

## Files

<path>
<path>

Generated outputs are not listed: regenerate them with the repo's own tooling.

## Gates

<the repo's own checks, as its instructions name them>

## Before starting

Re-verify each issue against the current tree. This bundle asserts the defects
were live at the SHA above and says nothing about now — and any version, URL,
tag or SHA quoted below is as old as the issue it came from, so look the
current value up rather than reusing it.

## Stop rule

If a fix turns out to need a judgment call, stop and report. Eligibility checked
each issue's body **and its comments** for an open question, and checked that
this repo names whatever the fix depends on. So finding an open question
falsifies the premise this bundle was built on rather than merely complicating
it — report it, do not decide it.
```

**The bundle has to carry what the thread said, not point at it.** This session
is discarded before the work starts — that is the whole design — so anything it
learned from a comment and did not write down is lost, and the working session
has no way to know it was ever there. A bundle is a device for *not* reading the
issue; it earns that only by carrying whatever reading the issue would have
supplied.

**Never restate a time-sensitive literal from an issue body as an instruction.**
A version, URL, tag or SHA quoted in an issue is only as current as the day it
was written, and a bundle promotes it from an example into a work order. Carry
the requirement and name the lookup: *"bump to the current stable line from
`releases.hashicorp.com`; the floor the estate needs is `>= 1.11`"*, never
*"bump to a 1.13.x"*. Bundle #459 did the latter, copying an example from an
issue written three weeks earlier, and the 1.13 line had been unpatched for ten
months by the time the bundle was worked (#474).

## 8. Report

Same rule as the plan: markdown, never a gutter-aligned fence.

> **Bundle result** — read `<N>` open issues at `<sha>`
>
> **Closed as already fixed:** `<k>` — #`<n>` (`<what fixed it>`)
>
> | Bundle | Concern | Closes |
> | --- | --- | --- |
> | #`<n>` | `<concern>` | #`<a>`, #`<b>` |
>
> - Clusters reported: `<c>`
> - Eligible but unbundled: `<u>`
> - Deferred: `<d>` — the backlog that actually needs you
> - Backlog: `<N>` open before, `<N-k+b>` now with the bundle issues,
>   `<N-k-closed-by-bundles>` once the bundle PRs merge

Link each bundle number to its issue, since the report is what the user clicks
from.

Two things about that last bullet. The bundle Issues make the count go **up** in
the short term; each one takes several issues with it when its PR merges, so the
net is sharply down, but the number moves the wrong way first and the report
should not hide it.

And the deferred list is the real output. After this runs, what is left
unbundled should be the work that genuinely needs a decision — which was the
point of separating it from the work that does not.

## Guardrails

- **Never use issue search to find or dedupe anything.** It is eventually
  consistent, so a just-created Bundle Issue can be invisible for minutes. List
  and filter client-side.
- **Never fix anything here.** This session triages. A tempting one-line fix is
  a singleton bundle, not an exception.
- **Never mark an issue `FIXED` on a failed string match alone.** The wording
  may have moved while the defect stayed.
- **Never bundle across repos.** A session works the repo it is in.
- **Never put two bundles on the same source file**, and never extend that ban
  to generated files.
- **Never bundle an issue with an open question**, however small the edit looks
  — and read its comments before deciding it has none.
- **Never bundle or close an issue on its body alone.** A body can be reversed
  by its own newest comment, and the issue that is about to be closed is exactly
  the one where missing that is expensive.
