# Review: mattpocock/skills against this repo's skills

- **Date**: 2026-11-20
- **Tracking**: [#786](https://github.com/pmgledhill102/agentic-coding-config/issues/786)
- **Source**: [`mattpocock/skills`](https://github.com/mattpocock/skills) at
  commit `abeeaf9` (2026-11-19), MIT licensed
- **Decisions arising**: none yet. Every suggestion here needs its own issue,
  and the review-time tier needs an ADR discussion

This review answers one question: which of the 39 agent skills in
`mattpocock/skills` deserve more time, with its `retro` skill compared in
detail with this repo's `retrospective`.

Paths under `skills/`, `docs/engineering/` and `.out-of-scope/` are in the
upstream repo. Paths under `home/`, `context/`, `tests/` and `ideas/` are in
this one.

## 1. Verdict up front

**This repo's retro is the more developed of the two.** The upstream docs page
for `retro` lists three weaknesses: it never audits what it proposed before, it
fills its categories with generic advice, and it sees one session only. The
redesign in #263 already fixed all three. Its shape should not be adopted.

**The upstream retro is better at one thing: deciding where a fix should
land.** It sends mechanical mistakes to a failing check and judgement calls to
a reviewer, and keeps prose in the implementer's context as the last resort.
Our lever table has no row for either. That is the idea to take.

**The skill most worth reading is `writing-for-agents`**, which the upstream
retro loads before it does anything else. It is a compact theory of what makes
a line of agent-facing text earn its place, and it gives our subtraction step
the yardstick it currently lacks. Five others are worth a proper read, twelve
hold one idea each, and twenty-one can be skipped.

| | Upstream | This repo |
| --- | --- | --- |
| Skills | 39 (27 shipped in the plugin) | 24 |
| Typed-only skills, which cost no context | 24 | 0 |
| Median lines per `SKILL.md` | 75 | 189 |
| Lines in the retro skill | 44 | 341 (346 in a sandbox) |

## 2. The two retros, side by side

Theirs is a short prompt that scans a session against seven categories and
hands back a ranked list. Ours is a ten-step procedure with a closed loop, a
proposal cap, tier pricing and durable outputs. They solve different halves of
the problem.

| | Upstream `retro` | Our `retrospective` |
| --- | --- | --- |
| Runs when | The user types `/retro`, after a session that went badly. The docs say a smooth session has little to teach | Every `end-session`, unprompted. An uneventful session ends with one observation row |
| Finds candidates by | Scanning seven categories: navigation, automated checks, coding standards, global AGENTS.md, tool economy, no-ops, information access. Each has a "use when" trigger | Working backward from the three biggest costs the session paid. No checklist; the 16-dimension scan was deleted on purpose |
| Evidence | The session's primary sources. Can be pointed at an earlier session's log from a fresh context | One line from the transcript per cost, taken from whatever is still in context |
| Limit | None. Ordered by severity | Three proposals, each priced on four criteria |
| Removal | Flags no-ops and oversized steering files, judged against one session | Four instruments: compose budget, rejection record, conformance failures, grep for siblings |
| Memory | None. "It does not store what happened" | Reads the last 3–5 journal entries and the fate of every issue it filed |
| Output | A list in chat. Nothing is written until the user picks one | A journal entry, issues routed by repo, fixes in place, a telemetry record |
| Where a fix lands | A check first, then the reviewer's standards file, then a doc or skill. AGENTS.md only for pointers | One of five levers (installs, skills, context, permissions/hooks, memory) at one of three prose tiers |

### Where ours is ahead

The upstream docs page (`docs/engineering/retro.md`) is unusually candid. Each
admission below describes a problem our design has a mechanism for.

> This is its weakest spot. … It does not audit the lint rules, hooks, or CI
> jobs it proposed last month. It sees one session, so it cannot tell you that
> a rule now fires too often or that the bug behind it is gone.

Our answer is step 1, close the loop.

> Once the job is finished, the AI tends to forget the struggles from the
> middle of the session and invents generic advice to satisfy the retro
> categories.

That is the docs page quoting a user. Our answer is that there are no
categories to satisfy.

> Treat the severity order as a first draft too, because a quiet, expensive
> mistake can rank below a loud, cheap one.

Our answer is recurrence and a tier price on every proposal.

The second quote matters most. It is an independent report of the failure
measured here when two or three of every seven or eight proposals were
accepted. Their category list is the thing #263 removed.

### Where theirs is ahead

The upstream retro ranks destinations by what they cost the agent doing the
work. Our tier price ranks three kinds of prose. Lined up from cheapest to
dearest, the two cover different rungs:

| Where a fix can land | Context cost | Upstream | Ours |
| --- | --- | --- | --- |
| A failing check | None. Lint rule, hook, test, CI job | First choice for anything mechanical | **No lever row** |
| Review-time standards | None for the implementer. Read by a reviewer holding only the diff | Home for judgement calls | **No tier** |
| Skill body or pointed-at doc | Paid on invoke | Yes | Yes, priced near zero |
| Skill description | Paid every session, per skill | Only for agent-invoked skills | Yes, priced low |
| Always-loaded policy | Paid every turn | Navigation pointers only | Yes, burden of proof |
| Installs, permissions, memory | None | Loosely, under tool economy and information access | Yes, three lever rows |

The top two rungs are free and ours cannot name them. That gap is odd given
how this repo actually works: `CLAUDE.md` lists 28 quality gates and
`tests/gates-wired.sh` exists to make sure each one runs. The repo practises
check-first. The retro text does not ask for it.

## 3. Four things to take from the upstream retro

Ranked by how much each would change our retro's output. Prices use the tier
vocabulary of ADR-0018.

### 3.1 Classify the mistake before choosing the lever: mechanical gets a check

> A **mechanical** one (a fixed syntactic pattern, a banned API, an import
> shape, a file-location rule) gets a deterministic check, full stop. …
> Default to building the check over writing the rule.

Source: `skills/engineering/retro/SKILL.md`, step 3.

- **Ours today**: step 3 offers two preventions, a lever pull or a product
  fix. Both variants of the lever table
  (`context/skills/retrospective/07-propose-workstation.md` and
  `07-propose-sandbox.md`) have the same five rows, and none is a check. A gate
  that would have caught an agent's mistake has to pass as a product finding or
  it has no cell to name.
- **Change**: add one sentence to step 3 that sorts each cost into mechanical
  or judgement, and a sixth lever row, *Check*, priced at zero context. Take
  their second rule with it: read the repo's existing gates first, because a
  check that exists but is unwired is the finding.
- **Price**: on-invoke skill body. About five lines across two fragments. It
  should lower the share of proposals that ask for always-loaded text.

### 3.2 Give the subtraction step a definition of dead weight

> Hunt **no-ops** sentence by sentence: an instruction the model already obeys
> by default pays load to say nothing. The test (does it change behaviour
> versus the default?) is model-relative.

Source: `skills/productivity/writing-for-agents/SKILL.md`, Pruning.

- **Ours today**: step 4 says to "find the paragraph in the offending fragment
  that earns its keep least" and stops there. The instruments say where to
  look. Nothing says what makes a line removable.
- **Change**: name four tests in step 4. A **no-op** is something the model
  does anyway. A **cache** restates something one command would show.
  **Sediment** describes a world that has moved on. **Duplication** is one
  meaning in two places. The upstream retro loads the whole guide up front for
  this reason, and `.out-of-scope/lazy-load-writing-for-agents.md` records a
  refused request to load it lazily, because a read-only retro still needs the
  definitions to judge with.
- **Price**: on-invoke skill body, about six lines. Or one skill description
  line if the guide is adopted whole.

### 3.3 Take evidence from the session log, not from what is left in context

> Read the primary sources for the session the user specifies. This may mean
> searching through session logs on this machine.

Source: `skills/engineering/retro/SKILL.md`, step 2.

- **Ours today**: step 3 asks for a line of evidence "from the transcript". By
  the time `end-session` reaches Phase 2, a long session has been compacted and
  Phase 1 has added its own output on top. The costs from the middle are the
  ones most likely to be gone.
- **Change**: when the session was long or compacted, send a fresh-context
  subagent to read the on-disk log and return the costliest moments with
  quotes: failed commands, retries, denied calls, repeated reads. Step 3 ranks
  what comes back. It also makes a retro possible for a session that ended
  without one.
- **Price**: on-invoke skill body. The log path differs by surface, so it
  belongs in the variant fragments.
- **Caveat**: a JSONL session log was confirmed to exist in the cloud sandbox
  this review ran in. Mining one was not tried. Logs can hold secrets, so the
  mask-by-allowlist rule applies to whatever the subagent quotes.

### 3.4 A fourth tier: standards the reviewer reads and the implementer does not

> The implementation agent has the most **context pressure**. … The review
> agent has the least context pressure - it receives a diff, so no exploration
> needed. … This means that the review agent should be responsible for
> imposing coding standards, not the implementation agent.

Source: `skills/engineering/retro/SKILL.md`, Reference.

- **Ours today**: all three tiers load into the agent doing the work.
  `profiles/claude-cloud-sandbox/CLAUDE.md` is 328 lines against a budget of
  328, and `home/CLAUDE.md` is 356 against 361. Subtraction can only delete.
- **Change**: a review-time file gives subtraction somewhere to move text to.
  Commit and PR style, single-concern PRs and the stacking rules can all be
  checked against a diff. The upstream `code-review` skill is the other half:
  one subagent for standards, one for whether the diff does what the issue
  asked.
- **Price**: frees always-loaded lines, at the cost of a review step that must
  run every time. A mistake is caught after it is made, so the trade is context
  for a round trip.
- **Caveat**: this is the largest of the four and amends ADR-0018's tiers. It
  is a decision to make before anything is built.

### What to leave behind

- **The seven-category scan.** Its acceptance rate was measured here and it was
  deleted. The upstream docs report the same failure from a user.
- **Present and stop.** The upstream retro leaves follow-through to the user.
  Ours files the issue, and the closed loop checks what became of it.
- **"AGENTS.md is for navigation pointers and little else."** The upstream
  `CLAUDE.md` is 33 lines because it governs one repo of prose. Ours carries
  policy for a whole estate. The direction of pressure is right; the absolute
  rule does not transfer.

### Retro shows up in two other places upstream

Both sample sessions, where ours runs on all of them.
`skills/in-progress/chief-of-staff` runs a retro on about one in five subagent
sessions and picks the ones that went wrong first. The example tasks in
`skills/in-progress/software-factory/EXAMPLE-TASKS.md` include a retro
triggered by one merged PR in ten, which reads the PR, its ticket, its reviews
and run logs, and proposes instruction changes as a PR of its own. Our
telemetry record already counts proposals per run, so it can show how often an
every-session retro ends with nothing to propose.

## 4. Five more worth a proper read

- **`writing-for-agents`** — 103 lines across two files. Context pointers, the
  two loads (context for the agent, cognitive for the human), completion
  criteria, leading words, and the warning that a prohibition makes the banned
  behaviour more available. `home/skills/retrospective/SKILL.md` is a fair test
  of it: step 9 tells the agent not to write to a file that was retired, and
  lines 210 and 333 each spend a paragraph on a past formatting incident with
  issue numbers. Those paragraphs are written for whoever edits the skill next,
  and the agent running the retro pays for them every time.
- **`triage`, for `.out-of-scope/`** — one file per rejected concept: the
  reason, and every request that asked for it. Triage reads the folder before
  recommending anything. Our retro rebuilds its rejection record on each run by
  reading closed issues across several repos. A file per retired category would
  make that a single read, and `bundle-issues` could check it too. This repo
  has `ideas/` for parked work and nothing for refused work.
- **`grilling`** — 30 lines. Asks every question whose prerequisites are
  settled in one round, attaches a recommended answer to each, words them so
  "yes" accepts the recommendation, and looks facts up itself. A good fit
  before an ADR, and for issues carrying `needs: decision`.
- **`diagnosing-bugs`** — the long form of the three-strikes rule. No
  theorising until one command exists that goes red on this bug, then three to
  five falsifiable hypotheses, then tagged debug logs that one grep removes. It
  would let a rule currently paid for on every turn live in a skill body
  instead.
- **`wizard`** — generates a bash script that walks a person through steps
  only they can do: opens each URL, takes each value with hidden entry, writes
  it to `.env` or a GitHub secret. A runnable form of what a `needs: local`
  issue describes in prose. The 197-line template is bash, so it needs checking
  against the bash 3.2 rule before it is trusted on macOS.

## 5. All 39 skills

Lines count `SKILL.md` plus its sibling reference files. "Typed" means only
the user can invoke it; "agent" means the model can reach for it too. A †
marks a skill judged from its description and README line only.

### Read properly (6)

| Skill | Bucket | Lines | Invoked | For this repo |
| --- | --- | --- | --- | --- |
| `retro` | engineering | 44 | typed | Covered in sections 2 and 3. Take the check-first rule and the reviewer split. Leave the category scan |
| `writing-for-agents` | productivity | 103 | agent | The top pick. Gives the subtraction step a definition of dead weight, and it is the lens for auditing long skill bodies |
| `triage` | engineering | 424 | typed | Read for the `.out-of-scope/` folder: a durable rejection record per concept. The state machine itself overlaps `bundle-issues` |
| `grilling` | productivity | 30 | agent | Rounds of questions with a recommended answer each. Useful before an ADR or on a `needs: decision` issue |
| `diagnosing-bugs` | engineering | 138 | agent | Feedback loop before hypothesis. The full version of the three-strikes and prove-the-check-can-speak rules |
| `wizard` | engineering | 241 | agent | A runnable runbook for `needs: local` steps. Template is bash; check it against bash 3.2 |

### One idea each (12)

| Skill | Bucket | Lines | Invoked | For this repo |
| --- | --- | --- | --- | --- |
| `code-review` | engineering | 89 | agent | The Spec axis: does the diff do what the issue asked? Matters if a review-time tier is added. Its name collides with the Claude Code built-in |
| `ask-matt` | engineering | 152 | typed | Its phase-boundary tree: continue, clear, hand off, subagent, compact, asked in that order. Our session skills cover the edges of a session and nothing covers the middle |
| `wayfinder` | engineering | 128 | typed | A map issue with decision tickets as sub-issues, wired with blocked-by. Both mechanisms already exist here. The fog-or-ticket test is the useful part |
| `pr` | engineering | 173 | agent | The Merge Danger section: one-way or two-way door, and blast radius. Relevant where a merge is a deploy |
| `domain-modeling` | engineering | 181 | agent | A `GLOSSARY.md` would give the retro's Phrasing items somewhere durable to land. Also a three-part test for when an ADR is warranted |
| `to-tickets` | engineering | 105 | typed | Expand, migrate, contract for wide refactors that cannot land green in one slice |
| `implement-spec` | engineering | 42 | typed | Works tickets as a graph with worktree subagents onto one integration branch. Worth a look if bundles are ever run in parallel |
| `handoff` | productivity | 16 | typed | Reference existing artefacts, never copy them. It saves to the OS temp directory, which the ephemeral-first rule would not accept as durable |
| `wait-what` | productivity | 7 | typed | One line: re-pitch the last message in Simplified Technical English. Costs nothing to try |
| `chief-of-staff` | in-progress | 75 | typed | Wiki rules: date every claim, cite the commit, never rewrite, supersede. Applies to journals and decision records |
| `software-factory` | in-progress | 516 | typed | Vocabulary for triggered agent runs, and the rule that every trigger needs a brake. Read if scheduled sessions grow |
| `loop-me` | in-progress | 32 | typed | Push right: do all the work first, ask the human once, late. Same idea as the Tier 2 batched confirmation |

### Skip (21)

| Skill | Bucket | Lines | Invoked | For this repo |
| --- | --- | --- | --- | --- |
| `grill-with-docs` | engineering | 7 | typed | A two-line wrapper over `grilling` and `domain-modeling` |
| `grill-me` | productivity | 7 | typed | A one-line wrapper over `grilling` |
| `to-spec` | engineering | 75 | typed | Product feature specs with user stories. Not the shape of work in this estate |
| `implement` | engineering | 17 | typed | Fetch ticket, TDD, review, commit. The issue workflow already says this |
| `research` | engineering | 12 | agent | Background agent, primary sources, cited file. The same rule is already in policy |
| `tdd` | engineering | 174 | agent | Sound, and aimed at application code. Keep in mind for product repos |
| `codebase-design` | engineering | 195 | agent | Deep-module vocabulary for application architecture |
| `improve-codebase-architecture` | engineering | 194 | typed | Architecture survey with an HTML report. Aimed at application code |
| `prototype` | engineering | 205 | agent | Throwaway UI and state-machine prototypes |
| `setup-matt-pocock-skills` † | engineering | 312 | typed | Per-repo config for their flow. The `setup-*` skills and issue conventions cover this |
| `to-questionnaire` | productivity | 54 | typed | Writes a questionnaire for someone else to fill in |
| `teach` † | productivity | 284 | typed | Multi-session tutoring workspace |
| `claude-handoff` | in-progress | 18 | typed | `handoff` plus `claude --bg`. Workstation only |
| `setup-ts-deep-modules` † | in-progress | 102 | typed | dependency-cruiser for TypeScript packages |
| `writing-beats` † | in-progress | 67 | typed | Article drafting |
| `writing-fragments` † | in-progress | 79 | typed | Article drafting |
| `writing-shape` † | in-progress | 79 | typed | Article drafting |
| `git-guardrails-claude-code` | misc | 95 | agent | Frozen. Their own notes list reported bypasses. This repo has `prepush-guard` and `credguard` |
| `setup-pre-commit` † | misc | 91 | agent | Husky and lint-staged. Frozen |
| `migrate-to-shoehorn` † | misc | 118 | agent | TypeScript test migration. Frozen |
| `scaffold-exercises` † | misc | 106 | agent | Course exercise scaffolding. Frozen |

## 6. How the upstream repo is run

Three habits outside the skills themselves that bear on this repo.

- **Typed-only skills.** Setting `disable-model-invocation: true` removes a
  skill's description from context. Upstream uses it on 24 of 39. Our 24
  descriptions total 5,881 characters, loaded every session. `bundle-issues`,
  `promote-journal-inbox` and `estate` look like candidates if they are always
  typed. `retrospective` cannot be one, because `end-session` calls it through
  the Skill tool and a typed-only skill is unreachable by other skills. The
  saving is small; it is the description tier the retro already prices.
- **An "observed failure" bar on the issue inbox.** The upstream `SCOPE.md`
  keeps an issue open only if it describes something that went wrong in a real
  session. It is the costs-first rule applied at the door, which would cover
  issues that reach this repo from other sessions as well as from retros.
- **"It's working if" on every docs page.** A few signals a user can see in
  their own work without opening the skill. It is a cheap first step towards
  the question `ideas/skill-evals.md` parks: whether a skill is earning its
  tokens.

One upstream convention cuts against one of ours. Their agent-brief guide
(`skills/engineering/triage/AGENT-BRIEF.md`) says an issue should never name
file paths or line numbers, because it may wait weeks and the code will move.
Our cross-repo rule asks for exact paths and the full snippet. We handle
staleness by re-verifying against the working tree in `bundle-issues`; they
handle it by writing at the level of behaviour. Both work. It is worth knowing
the choice exists.

## 7. A suggested order

1. Read `writing-for-agents` and its docs page. Ten minutes, and it changes how
   the rest reads.
2. Add the mechanical-or-judgement sort and the Check lever to the retro.
   Small, and all on-invoke.
3. Add the four dead-weight tests to step 4.
4. Decide whether rejected categories get a file of their own.
5. Try log-mined evidence in one long sandbox session before writing it into
   the skill.
6. Take the review-time tier to an ADR discussion. Do this one last.

The upstream repo is MIT licensed, so lifting text with attribution is fine.

## 8. Method and limits

- Cloned `mattpocock/skills` at `abeeaf9`. Read 28 skills in full with their
  reference files, 2 in part (`codebase-design`, `git-guardrails-claude-code`),
  and judged 9 from descriptions (marked † above).
- Read `home/skills/retrospective/SKILL.md` in full, both lever-table variants,
  and the compose budget report from `tests/compose-context.py`.
- None of the upstream skills were run, so every claim about their behaviour is
  from reading the text.
- Figures for this repo (line counts, budgets, description totals) are as of
  2026-11-20 and will drift.
