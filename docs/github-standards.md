# GitHub estate standards

The normative standard for every repository under `pmgledhill102`. This
document says what a repo's GitHub-side configuration should be and why;
it deliberately does not say what any repo's configuration currently is.
Audits, per-repo tier assignments and the archive list are private and live
in `paul-context` (`registry/`, `tools/repo-audit.sh`) — the split is:
**standard public, evidence private**.

Status: accepted 2026-08-29. Required-check *contexts* remain repo-specific
for now — see [Checks and CI](#checks-and-ci) for what is settled and what
is deferred.

How this document relates to the rest of the estate:

- **The values live in [`home/standards/github-repo.json`](../home/standards/github-repo.json).**
  This document is the rationale; the spec is what `/setup-repo` applies
  and the estate audit diffs against, in the GitHub API's own field names.
  A value stated here and not there is not standard — change both in the
  same PR.
- **Skills in this repo apply it.** `/setup-repo` sets the remote half,
  `/setup-common` the in-repo half. Where a skill's instructions and this
  document disagree, this document wins and the skill has a bug.
- **Verification lives in `paul-context`.** `tools/repo-audit.sh` reads the
  live estate and compares it against this standard. Settings are not
  behaviour (see [Verification](#verification-settings-are-not-behaviour)),
  so the audit is a standing capability, not scaffolding.
- **A repo may deviate, but only explicitly**, per
  [ADR-0015](https://github.com/pmgledhill102/agentic-coding-config/blob/main/adrs/0015-tiered-adrs.md):
  a repo-tier ADR naming what it deviates from and why. Silent divergence is
  the failure this document exists to prevent.

## Account context

The estate is a **personal GitHub Pro account**, not an organisation. Both
halves of that matter.

**Pro is load-bearing.** Rulesets and branch protection on **private**
repositories require a paid plan; on Free they are limited to public repos.
Most of this estate is private, so nearly every rule below works *because*
of the Pro subscription. If the plan ever lapses, enforcement silently
stops on private repos — the rules remain visible in settings but stop
applying, which is exactly the "looks configured, isn't" failure mode this
document is written against.

**Personal means per-repo, always.** Organisation-level rulesets, org
security defaults, and org-wide required workflows are unavailable. Every
standard here is applied N times by script and verified by audit, never
defined once and inherited. Two consequences:

- The apply mechanism is a scripted `gh` sweep plus re-runs of the setup
  skills — decided in `paul-context`
  `decisions/2026-08-18-repo-standards-mechanism.md` (not Terraform, not a
  `.github` defaults repo).
- Verification is first-class, because nothing converges automatically.

If the estate ever moves into an organisation, revisit this whole document:
org rulesets change the arithmetic completely.

## Merge methods

The standard repository signature:

| Setting | Value |
| --- | --- |
| Allow merge commits | **on** |
| Allow squash merging | **on** |
| Allow rebase merging | **off** |
| Automatically delete head branches | on |
| Allow auto-merge | on where CI gates exist (see Dependabot) |

Merge-commit is the default method; squash is for a branch genuinely
carrying WIP or fixup noise; rebase-merge is disabled outright. The full
rationale lives in the Git Workflow section of the composed agent policy
(`context/fragments/core.md`) — in one line: squash and rebase both rewrite
the branch's commits to new SHAs, which punishes anything stacked on the
branch, and squash additionally drops commit-message trailers, so a
`Closes #N` in a commit message silently fails to close the issue.

Two operational facts, both learned the hard way on 2026-08-29
(agentic-coding-config#348 carries the evidence):

- **The merge dropdown is sticky per user per repository.** GitHub
  pre-selects whatever method was last used on that repo, not the "best"
  enabled one. Re-enabling merge commits on a repo that has been
  squash-only does not change what the button does next time; the first
  merge after a settings fix must change the dropdown by hand, once.
- **Never require linear history** (a ruleset/protection rule, not a
  repo setting). It forbids merge commits on the branch regardless of the
  repo-level toggles, and the failure appears at merge time on an approved,
  green PR — far from the setting that caused it. A repo can carry
  `allow_merge_commit: true` and still be unable to merge; only the branch
  rules reveal it.

Commit-message formats, so `main` reads identically whichever method a PR
used:

- Merge commits: title `PR_TITLE`, body `PR_BODY` (API-only; `gh repo edit`
  has no flag for this pair)
- Squash: title from PR title (`--squash-merge-commit-message pr-title`)

## Branch rules: rulesets, not classic protection

**Rulesets are the standard. Classic branch protection is legacy** —
migrate on touch, don't build anything new on it.

Why rulesets, concretely:

- **One addressable object.** A ruleset is created and updated as a single
  JSON document; classic protection can only be changed by `PUT`ing the
  entire protection object, whose request shape differs from the `GET`
  response shape, so scripting it across the estate risks silently dropping
  rules. For a per-repo estate applied by sweep, this difference is
  decisive.
- **One place to look.** Classic rules and rulesets can both apply to the
  same branch, most-restrictive-wins — which means a blocking rule can hide
  in either layer. Standardising on one collapses the search space
  (the 2026-08-29 linear-history hunt was this exact cost).
- **Bypass is an actor list with an audit log**, not an all-or-nothing
  admin checkbox.
- **Dry-run exists**: a ruleset can be created in *evaluate* mode to see
  what it would have blocked before enforcing it.

GitHub ships a one-click migration
([changelog, 2026-08-11](https://github.blog/changelog/2026-08-11-automatically-migrate-branch-protection-rules-to-repository-rulesets/)):
repo Settings → Branches → the classic rule → **Convert to ruleset**.

### The standard ruleset (default branch)

One ruleset per repo, targeting the default branch:

| Rule | Setting |
| --- | --- |
| Require a pull request before merging | on; required approvals **0** |
| Require status checks to pass | on; contexts are per-repo (see Checks) |
| Block force pushes | on |
| Restrict deletions | on |
| Require linear history | **off — prohibited**, see Merge methods |
| Bypass list | empty by default; add the narrowest actor only when something breaks without it |

Required approvals is 0 because this is a single-human estate: requiring an
approval the same human must give adds a click, not a control. The PR
itself (and its CI) is the control. Revisit per-repo if a repo ever gains a
second maintainer.

### Migration order and the auto-merge hazards

Do not sweep-convert the estate blind. Two known hazards sit exactly where
this estate lives (Dependabot auto-merge):

1. Reports of **auto-merge never firing after a ruleset migration**
   ([community discussion](https://github.com/orgs/community/discussions/162623))
   — enabled, checks green, merge doesn't happen.
2. A **2026-03 behaviour change**: enabling auto-merge now fails (HTTP 422)
   until all PR requirements are already met
   ([community discussion](https://github.com/orgs/community/discussions/190610))
   — and the Dependabot workflow enables auto-merge at PR-open time, before
   checks finish.

So the protocol is: **convert one repo that runs the full Dependabot
auto-merge apparatus, let one real Dependabot PR through end-to-end
(approve → auto-merge arms → checks pass → merge commit lands), and only
then convert the rest.** If hazard 2 bites, the workflow needs a
wait-for-checks step before `gh pr merge --auto`; fix that in the reference
repo first so the sweep propagates the working shape.

## Pull request templates

Every active repo carries `.github/pull_request_template.md`. The template
is a layout for describing the change, not a form to satisfy:

- Sections: summary, type of change, checklist of the repo's own quality
  gates, anything the repo specifically needs (e.g. a Terraform repo asks
  for the plan output).
- Keep the checklist honest: list only gates that exist and can be run.
  A checklist item nobody can execute trains readers to tick boxes.
- N/A answers are answers — "no Terraform in this change, so there is no
  plan" beats a deleted section, because it shows the question was asked.

## Dependabot

The full standard — including why each piece exists and the per-repo tier
assignments — is `paul-context/registry/dependabot-standard.md` (private,
because the tier list names private repos). The normative summary:

**The system has two halves, and each is invisible from the other.** Repo
*settings* (dependency graph, alerts, security updates) are what raise an
alarm when an advisory lands; repo *files* (`dependabot.yml`, the
auto-merge workflow) are how routine bumps arrive. Weekly bump PRs prove
only the file half. A repo shipped bump PRs for months, on schedule,
correctly labelled, while alerts — the half that reports a compromised
dependency — were off.

Settings half (every active repo, and cheap enough for dormant ones):

- Dependency graph **on** (private repos: must be enabled explicitly;
  nothing else works without it)
- Dependabot alerts **on**; security updates **on**; grouped security
  updates **on**

File half (repos with CI worth trusting):

- `dependabot.yml`: weekly schedule; patch+minor grouped per ecosystem;
  majors arrive alone (they are the ones worth reading); **cooldown on
  every ecosystem entry** — auto-merge without a cooldown ships a
  compromised release the moment CI goes green. Caveat: the per-severity
  cooldown keys are accepted by some ecosystems only, and a rejected key
  invalidates the **entire file**, silently stopping every update stream in
  the repo — add keys to a new ecosystem only after checking they are
  accepted.
- Auto-merge workflow: approves and auto-merges **patch/minor only**;
  majors always wait for a human. Both the approval and the merge use a
  fine-grained PAT, not `GITHUB_TOKEN` (Actions may not approve PRs, and a
  `GITHUB_TOKEN` merge does not trigger the workflows that run on push to
  the default branch — deploy pipelines silently stop firing). The PAT
  lives in the **Dependabot** secret store, not Actions — Dependabot-triggered
  runs read from the Dependabot store, and a secret in the wrong store is
  simply empty at run time, with no error. The workflow fails loudly when
  the PAT is missing rather than falling back.
- Merge flag: `--merge`, per the merge-methods standard.

### The `AUTOMERGE_PAT`: one shared token for the estate, not one per repo

Decided 2026-08-29. The auto-merge PAT is a **single shared fine-grained
token**, whose selected-repositories list is exactly the set of repos
running the auto-merge apparatus — no wider.

- **Permissions: Contents read/write, Pull requests read/write, and the
  forced Metadata read. Nothing else.** This is the floor, not an
  over-grant: the approval needs the pull-requests half, and the merge
  itself writes commits to the base branch — GitHub has no narrower
  "may merge but not push" permission, so Contents write cannot be
  trimmed away.
- **Storage stays per-repo even though the token is shared.** A personal
  account has no organisation secrets, so the same token is stored under
  the same name in each repo's Dependabot store, which keeps the workflow
  file byte-identical everywhere. Distribution and rotation are one loop:

  ```sh
  for r in <tier-2 repos>; do
    gh secret set AUTOMERGE_PAT --app dependabot --repo "pmgledhill102/$r" --body "$TOKEN"
  done
  ```

- **Why shared:** per-repo tokens multiply minting, expiry tracking and
  rotation by the repo count to buy isolation between repositories that
  all have the same owner — the blast-radius argument that justifies
  per-repo credentials in a multi-tenant organisation does not apply
  here, and every extra token is another row the PAT inventory has to
  account for. Widening the covered set is an edit to the token's repo
  list plus one loop iteration, never a new credential.
- **What bounds a leaked token is the ruleset, not the token's scope.**
  The standard ruleset requires a pull request and passing checks on the
  default branch, with an empty bypass list — so even a stolen
  `AUTOMERGE_PAT` cannot land anything on a default branch without real
  CI going green first, and cannot push to it directly at all. This is
  load-bearing, which is why **the token's repository list and the
  ruleset rollout must be the same list**: a repo reachable by the token
  but lacking the ruleset has none of that protection.
- **The token's coverage cannot be audited.** A fine-grained PAT's
  repository list is not readable from outside the token, so no sweep can
  answer "is this repo actually in scope?" — only using the token answers
  that. A repo added to the auto-merge tier but missed off the list fails
  at run time, and fails *confusingly*: the secret is present and
  non-empty, so the workflow's missing-PAT guard passes, and the failure
  surfaces as a raw 403 from the approve step. Two controls follow, and
  they are the only two available: add the repo to the token's list as an
  explicit step when the auto-merge workflow is installed, and have that
  workflow name this cause when the approve step fails.
- **Upgrade path, recorded rather than adopted:** a private GitHub App
  with the same two permissions, installed on the same repo list, minting
  short-lived installation tokens per run — no expiry dates, no rotation.
  It also fixes the unauditability above: an App's coverage *is* readable,
  one call per repo (`GET /repos/{owner}/{repo}/installation`), so a sweep
  can prove coverage instead of discovering a gap at run time. Adopt it
  the first time PAT rotation actually hurts, when a missed repo has
  cost real debugging, or if the estate ever becomes an organisation;
  until then it is more moving parts than the problem needs.

This posture matches GitHub's own 2026 guidance
([grouping, cooldown, security-fast](https://github.blog/security/supply-chain-security/tame-dependabot-group-your-updates-slow-the-cadence-keep-security-fast/));
the estate's 7-day cooldown is stricter than the platform's 3-day default,
deliberately.

**The combination that must never exist: auto-merge enabled with no
required status checks on the default branch.** Without required checks,
`gh pr merge --auto` merges *immediately* — the "wait for CI" everyone
assumes is supplied by the ruleset, not by the flag.

## Checks and CI

Settled 2026-08-29: **required-check contexts stay repo-specific for now.**
The ruleset migration carries each repo's existing required checks across
as they are; standardising which contexts every repo must require is
deferred until after the migration, so the two changes cannot be confused
with each other when something breaks.

Current practice, from `/setup-common`: every repo gets gitleaks, cspell
and semgrep jobs plus actionlint; language skills add their gates; GitHub
Actions are pinned to commit SHAs.

One rule is estate-wide **now**, because it is a safety invariant rather
than a convention:

- **A repo with auto-merge enabled must require at least one status
  check.** Without one, `gh pr merge --auto` merges immediately — see the
  Dependabot section's never-combination. If a repo has no check worth
  requiring, it does not get auto-merge.

Deferred until after the migration, recorded so the discussion has a home:

- **Which contexts are *required*** (ruleset-enforced) versus merely run.
  Required contexts are named by job, so renaming a job silently detaches
  it from the ruleset — a naming-stability convention is the prerequisite
  for requiring aggressively, and should be decided before contexts are
  standardised.
- Whether a uniform minimum (lint + secrets) should be required on every
  active repo, with language gates required only where the language exists.
- Whether path-filtered workflows can be required at all (a required check
  that doesn't run on a docs-only PR blocks the merge unless a
  skipped-equals-passed pattern is adopted).

## Verification: settings are not behaviour

The recurring failure across the estate is a system that *looks* configured:
settings that were never applied, applied then contradicted by another
layer, or applied but with their effect quietly blocked. Three instances,
one month:

- a repo bumped dependencies weekly while advisory alerts were off;
- a repo carried `allow_merge_commit: true` while a linear-history rule
  made merge commits impossible;
- repos carried `allow_auto_merge: true` with no required checks, making
  "auto-merge when green" actually "merge now".

So the standard includes its own verification discipline:

- **Declared state**: `paul-context/tools/repo-audit.sh` sweeps the estate
  and diffs it against the spec, `home/standards/github-repo.json`. Run it
  after any sweep, and occasionally between. Until the audit's cut-over to
  reading the spec lands (tracked in `paul-context`), it carries its own
  copy of the expected values — the drift the spec exists to end.
- **Observed behaviour**: after remediating a repo, watch the first PR
  through — the merge commit exists (`git log --merges --since=<fix date>`;
  date-bound it, or early history satisfies the check vacuously), the
  Dependabot PR actually merged itself, the deploy workflow actually fired.
  A settings read alone has signed off on broken repos three times; the
  behavioural check is the one that counts.

## Tiers

Not every repo earns the full apparatus, and the axis is **consequence**:
what happens if a dependency in the repo turns out to be compromised. Not
how active the repo is, not whether it is public. Three tiers, each
extending the last, defined in the spec:

| Tier | Applies to | Adds |
| --- | --- | --- |
| `baseline` | every repo | dependency graph, alerts, security updates |
| `protected` | deployed or reachable | the merge-methods signature, the standard ruleset |
| `automerge` | protected, and CI proves something | auto-merge, a required-checks rule, `AUTOMERGE_PAT` |

Which repo sits in which tier is private, in `paul-context`: the spec
carries the tiers, the private registry carries the assignments. The
Dependabot tiers in that registry are the *file* half of the same idea;
these are the settings half, and its Tier 0 is `baseline`, its Tier 2
`automerge`.

## Applying this standard

- **New repo**: run `/setup-repo` and `/setup-common` at creation. Both
  must land the repo on this document's values; where they don't, the skill
  has a bug — fix the skill, don't hand-patch the repo.
- **Existing repos**: scripted sweep + audit, per the mechanism decision in
  `paul-context`. Archive first; sweep the smaller estate.
- **Changing this standard**: one PR against this file **and the spec**
  (`tests/github-repo-standard.py` keeps the spec self-consistent), then a
  sweep to apply it and an audit run to confirm — a standard changed
  without a sweep is just a wish.
