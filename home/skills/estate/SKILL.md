---
name: estate
description: 'Survey open work across every repo in the estate in one read-only pass: issue and PR counts per repo, P0/P1 listed individually, Dependabot separated from human PRs, and one flag per repo ordered so the top of the table is where attention belongs. Use when deciding what to pick up next, when asking which repo is in the worst shape, or for a periodic review of the whole estate.'
---

# Survey the estate's open work

One pass over every repo, producing a table whose top rows are the answer to
"what should I work on". Read-only: this skill creates nothing, closes nothing
and pushes nothing.

## What it answers, and what it deliberately does not

Counts tell you where the **volume** is. They never tell you where the **pain**
is — a repo with 40 tidy P3s is healthier than one with a single P0 and no
commits for six weeks. So the table carries counts, but it is *ordered* by
flags, and the flags are the product.

Three neighbours already own the questions this one does not ask:

| Question | Owner |
| --- | --- |
| Is the estate configured correctly? | `paul-context/tools/repo-audit.sh` |
| What has rotted inside *this* repo? | `repo-review` |
| What are the workable units in this backlog? | `bundle-issues` |

The division worth remembering: **this skill says which repo to open;
`bundle-issues` says what to do once you are in there.** Do not grow a settings
check here — `repo-audit.sh` owns that, and two answers to one question drift.

## Never put estate data in this file

This repo is public. The skill body is a **method** and stays public; its output
is **evidence** and is never committed anywhere. That is the same
standard-public / evidence-private line the estate already runs for settings
audits.

The failure mode is specific and likely: you run this, the table looks good, and
it gets pasted into this file as "example output" — at which point a public repo
carries an estate inventory. The example below uses invented repo names for
exactly that reason. **Keep it that way**, and apply the same rule to any issue
or PR discussing this skill.

Output belongs in the session, or in the scratchpad. Nowhere else.

## Action tiers

- **Tier 1 — auto-act**: all of it. Every step is a read.

There is no tier 2. If a run ever wants to write something, that is a different
skill.

## Step 1 — Enumerate the estate

```text
mcp__github__search_repositories  query: "user:pmgledhill102 archived:false"
```

**Keep forks.** This is *not* `repo-audit.sh`'s exclusion rule. That sweep drops
forks because upstream owns their settings — settings-scoped reasoning. A fork
under this account can carry its own issues and PRs, which is work, so it stays.

Archived repos are excluded: they have no actionable work by definition.

Caveat to state if a repo you expect is missing: the search index is eventually
consistent, so a repo created in the last few minutes may not appear. The exact
fallback, where `gh` is present, is `gh api /user/repos --paginate`.

## Step 2 — Gather, two calls per repo

Issues and PRs are separate calls. `mcp__github__list_issues` is GraphQL-backed
and its `issues` connection **excludes pull requests** — the REST shortcut where
`/issues` returns both applies only to the `gh api` fallback path.

```text
mcp__github__list_issues         state: OPEN, perPage: 100,
                                 fields: [number, title, labels, created_at]
mcp__github__list_pull_requests  state: open, perPage: 100,
                                 fields: [number, title, user, created_at, draft]
```

**Always pass `fields`.** Both tools return very large payloads otherwise, and
`body` alone will overflow the result across ~40 repos. Nothing here needs
bodies: titles, labels and dates carry every signal the table uses.

**The read is not atomic.** With `perPage: 100` most repos return in a single
call, and that repo's figures are a true snapshot. Where a repo needs paging,
the set can move underneath you between calls.

Observed while building this: a first page reported `totalCount: 80` and a
second `63`. Neither was wrong — roughly twenty issues were genuinely closed in
a concurrent session between the two calls, and each figure was accurate for
its moment. The unreliable number was the one derived by summing rows across
both pages, which splices two different points in time.

So: page until `hasNextPage` is false using `after: <endCursor>`, and print the
run's start time so the table carries its own as-of. A multi-page repo's numbers
are a smear across the run, not a snapshot — which is fine for choosing where to
spend a day, and not fine for anything that needs to reconcile.

**Do not conclude the API is wrong.** Two figures disagreeing across calls is
far more likely to be concurrent work than a platform defect, and this estate's
standing rule is to treat "the platform is broken" as the last hypothesis.
Sessions run in parallel here; the backlog moving mid-read is normal life.

Never use `search_issues` for this. It is eventually consistent, and a backlog
view built on a stale index reports confident wrong numbers.

For last-commit date, read it from the repository record returned in step 1
(`pushed_at`) rather than spending a call per repo.

## Step 3 — Derive

### Buckets

From each issue's labels:

- **P0-1** — carries `P0` or `P1`. Collect these **in full**, with repo, number
  and title; they are listed individually above the table.
- **P2-4** — carries `P2`, `P3` or `P4`. Count only.
- **untriaged** — carries no `P*` label at all. Count only.

Untriaged gets its own column rather than being folded into P2-4. Hiding it
understates the backlog and conceals triage debt, which is itself a finding.

### Human versus bot PRs

Split by author: `dependabot[bot]`, `renovate[bot]` and similar are bot PRs.
They are a **different kind of number**, not a smaller queue:

- A human PR open more than 7 days is a review bottleneck. Since the estate's
  convention is not to merge your own PRs, open human PRs *are* the chokepoint.
- Twelve Dependabot PRs at 40 days old is **one config bug**, not twelve pieces
  of work — auto-merge is not firing. Diagnosis lives in `repo-review` F3:
  `AUTOMERGE_PAT` present, required status checks configured.

Report bots as `count, oldest Nd`. Zero to two is normal churn; render it, but
do not let it raise a flag.

### Flags

Assign each repo **at most one** flag, first match wins:

| Flag | Trigger |
| --- | --- |
| `P0` | any open P0 |
| `blocked` | a human PR open more than 7 days |
| `automation` | 5+ bot PRs with the oldest over 14 days |
| `stalled` | an open P1 and no push in 30 days |
| `untriaged` | more than 5 unlabelled issues |
| `quiet` | no open issues and no open PRs |

A repo matching none of these — open work, actively pushed, nothing overdue —
is **unflagged**, and that is a real and common state rather than a gap in the
table. Render it with an empty flag and sort it below every flagged repo and
above the quiet ones. Resist the urge to invent a flag for it: a large backlog
that is being worked is exactly the case the flags exist to *not* raise, and
this skill is worth little if volume alone can set off an alarm.

Sort the table by this order. The top five rows are the answer to the question
that prompted the run.

**Do not compute a composite score.** A single blended number cannot be checked
against intuition, so it stops being believed within a month — and an ordered
flag is the same information in a form that survives disagreement.

## Step 4 — Render

Print two blocks. Keep fences under ~80 columns so they survive a terminal
without wrapping.

First, the exceptions — every P0 and P1 in the estate, by title:

```text
P0 / P1 across the estate (7)

  P0  repo-alpha#211   Token refresh drops the retry budget
  P0  repo-beta#18     Nightly export writes to the wrong bucket
  P1  repo-alpha#204   Migration runner has no rollback path
  ...
```

Then the table, flagged repos first, quiet ones collapsed:

```text
repo             open  P0-1  P2-4  untri  PRs(you/bot)  push   flag
--------------------------------------------------------------------
repo-alpha         41     3    31      7    2 / 0        2d    P0
repo-beta          12     1     9      2    0 / 9       31d    automation
repo-gamma          6     0     5      1    1 / 0       14d    blocked
repo-delta         23     1    22      0    0 / 1       48d    stalled
repo-epsilon        9     0     2      7    0 / 0        5d    untriaged
repo-zeta          78     2    71      5    0 / 0        0d
repo-eta           14     0    14      0    1 / 2        3d

quiet (11): repo-theta, repo-iota, repo-kappa, ...
```

Close with two or three sentences naming where you would spend the time and
why — the flags are evidence for a recommendation, not a substitute for one.

### JSON interchange

Write the collected data to the session scratchpad as JSON before rendering.
It costs nothing, makes a second renderer cheap later, and lets a follow-up
question be answered without re-running ~80 calls.

**Scratchpad only.** It is regenerable output, so committing it would put
estate evidence in a public repo and violate the rule above twice over.

## Degradation

An unreachable repo reports as **unchecked**, never as clean. Print a
`not checked (<reason>)` line naming each one. A silently dropped repo is
indistinguishable from a healthy one, which is the exact failure this skill
exists to catch.

Prefer `mcp__github__*` throughout. Where the MCP server is unavailable and
`gh` is present, the REST fallbacks are noted per step — but note that `gh`'s
GraphQL-backed commands (`gh pr list`, `gh pr view`) fail in a Claude Code
session regardless of whether the binary is installed, so the fallback is
`gh api` against REST endpoints, not the porcelain.

## Footnotes

- **CI status is deliberately absent.** Per-PR check runs are a call each and
  would multiply the run's cost several times over. If `automation` or `blocked`
  fires and you want to know whether CI is red, fetch it for that repo alone.
- **Not part of `start-session`.** That skill is per-repo and already heavy;
  this one is a deliberate weekly "what should I pick up" act. A one-line
  summary read from cached JSON could surface there later without moving the
  work.
- **Roughly 80 calls, a few seconds.** Cheap enough to run weekly, too heavy to
  run at every session start — which is the same conclusion from the other side.
- **No HTML renderer yet.** When one is wanted, build it over the JSON rather
  than the console output, and publish it as an Artifact — a file written to
  `/tmp` dies with the container and cannot be opened from a sandbox anyway.
