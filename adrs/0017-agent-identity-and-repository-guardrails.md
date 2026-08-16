# ADR-0017: Agent identity, repository guardrails, and access control as code

- **Status**: Proposed (2026-08-16)
- **Date**: 2026-08-16
- **Tags**: security, github, agents, identity, access-control
- **Scope**: user (applies to all personal repos and agent surfaces)

## Context

`CLAUDE.md` carries a rule — no direct push to `main`, no unreviewed
merge — that has been ignored more than once. An audit of this repo on
2026-08-16 explains why: nothing enforces it.

| Finding | Evidence |
| --- | --- |
| `main` has no branch protection | `list_branches` returns `protected: false` |
| Cloud sessions act as the human, with admin | `get_me` returns `pmgledhill102`, repo `permissions.admin: true` |
| Approvals are structurally impossible | `setup-repo` hardcodes `required_pull_request_reviews: null`, commented *"solo developer — cannot require approvals from others"* |
| Pushes are unrestricted client-side | `home/settings.json` allows `Bash(git push *)` with no prompt |
| Merge is one click from unsupervised | `mcp__github__merge_pull_request` is not allow-listed, but not denied either |

The rule was never enforced anywhere. It was a sentence in a file that
the agent bound by it could also edit.

Two further facts frame the options.

**Cloud sessions authenticate as a user, not as a bot.** The Claude Code
on the web documentation is explicit: a cloud session can access any
repository *the connecting GitHub account* can see, and App installation
"is not a session-level access control"; PR replies "are posted using
your GitHub account, so they appear under your username". Tightening the
Claude GitHub App's permissions on a repo therefore cannot change the
session's identity or take admin away — the token inherits the
connecting account's role. The only lever on identity is **which GitHub
account is connected to the Claude account**.

**Cloud is now the primary surface.** Most work is moving to cloud
sessions, so a control that only binds the local CLI is close to
worthless.

## Primer: what each control mechanism actually does

A short reference, because these are routinely conflated.

| Mechanism | What it is | What it enforces | What it does not do |
| --- | --- | --- | --- |
| **Repository role** | Read / Triage / Write / Maintain / Admin, per collaborator | The ceiling on everything else. Write can push and open PRs; only Admin can change protection rules | Does not distinguish *what* is pushed — a Write collaborator can push anything, anywhere the rules allow |
| **Branch protection (classic)** | The older per-branch settings page | Require PRs, approvals, status checks; block force-push and deletion | Being superseded by rulesets; one rule per branch pattern, no layering |
| **Rulesets** | The modern replacement. Repo- or org-level, layered, with an explicit bypass list | Same controls as above, but multiple rulesets can stack and the bypass list is auditable | Cannot stop a repo Admin from editing the ruleset itself |
| **Required status checks** | Named CI checks that must report success | Blocks merge until CI is green | Names are opaque strings — rename a job and it is required forever and never reports |
| **Required approvals** | `required_approving_review_count: N` | N humans must approve before merge | GitHub forbids approving your own PR, so a solo owner with a single identity can never satisfy `N >= 1` |
| **Require last push approval** | Extra ruleset flag | The most recent pusher cannot be the approver | With one human it deadlocks any PR that human pushed to |
| **CODEOWNERS** | A file mapping path globs to owners | Combined with "require review from Code Owners", forces the named owner to approve changes under those paths | Only affects *review requirements* on PRs. Does nothing about direct pushes |
| **Fine-grained PAT** | A per-repo, per-permission token tied to a user account | Whatever subset of that user's rights you grant it | Still acts as that user; expires and needs rotation |
| **GitHub App** | An installable identity with its own permissions and short-lived tokens | Acts as `app[bot]`, genuinely separate from any human | Cannot be used by Claude Code cloud sessions, which authenticate as the connecting user |
| **Deploy key** | An SSH key scoped to one repo | Git push/pull only | No API access — cannot open or review PRs |
| **Commit signing** | SSH or GPG signature on each commit, plus the Verified badge | Makes authorship cryptographic instead of self-asserted | Only meaningful if each actor holds a *different* key |
| **Claude Code `permissions` / hooks** | `allow`/`deny` lists and `PreToolUse` hooks in `settings.json` | Fast, local feedback before a command runs | Client-side. The agent can edit the file that constrains it, so this is ergonomics, not security |
| **Environments** | Deployment targets with required reviewers | Gates *deployments* | Does not gate merges |
| **Security log** | The account's audit trail at `github.com/settings/security-log` | A record of privileged actions | Records the *account*, so it cannot separate agent from human while they share one |

The pattern worth internalising: **server-side rules bind everyone;
client-side rules bind only the cooperative.** Everything in
`settings.json` and `home/bin/*` is the second kind.

## The gate

The requirement is a human decision point on every change reaching
`main`. The mechanism is negotiable — a submitted approval, a merge
button click, or anything else — but the gate must exist and must be
enforced by GitHub rather than by prose.

This matters for the options below, because a merge-button gate needs no
second identity, while an approval gate does.

## The contribution-statistics question

A separate identity was previously rejected because it appeared to cost
personal recognition for work that is real — design direction, review,
20+ hours a month — even where the lines are not hand-typed. That
concern deserves numbers rather than intuition, and the numbers are not
what they appear.

**What GitHub counts** toward the contribution graph: commits where you
are the *author* (with an email linked to your account) on the default
branch, issues opened, pull requests opened, and pull request reviews
submitted.

**What it does not count**, confirmed by GitHub staff as intended and
long-standing behaviour: `Co-authored-by:` trailers. Co-authorship
gives attribution in the commit and the PR, but no graph credit. Nor
does being *added* as a reviewer or assignee — only actually submitting
a review counts.

Applied to this repo as it stands today:

| Activity | Author today | Counts for the human? |
| --- | --- | --- |
| Code commits, local CLI sessions | `Paul Gledhill <github@pmgledhill.com>`, with a `Co-Authored-By: Claude` trailer | Yes |
| Code commits, cloud sessions | `Claude <noreply@anthropic.com>`, which GitHub maps to the unrelated `claude` account | **No** |
| Merge commits | `Paul Gledhill`, created by clicking Merge | Yes |
| PRs opened | The human's token, so the human | Yes |
| Issues opened | The human's token | Yes |
| Reviews | None — no approval is required | No |

Commit attribution therefore tracks **the surface the session ran on**,
not who wrote the code. Cloud environments set their own git identity
(`user.name=Claude`, `user.email=noreply@anthropic.com`) because signing
credentials are held outside the sandbox; the local CLI leaves the user's
git config alone and adds a co-author trailer instead.

The 91 non-merge commits in this repo make the effect concrete:

| Origin | Count | Graph credit |
| --- | --- | --- |
| Cloud sessions, authored `Claude` | 38 | None |
| Local sessions, authored human, Claude co-authored | 43 | Full |
| Hand-written, no Claude involvement | 8 | Full |
| Dependabot | 2 | n/a |

The same collaboration is recorded two different ways depending on
whether the session ran in a terminal or a browser. So roughly 42% of
agent-assisted commit credit has already been forfeited — by the move to
cloud sessions, which began 2026-08-04, and not by any identity
decision. Moving primarily to cloud forfeits the rest.

This does not change what Option 2 costs, because a bot account governs
the *GitHub connection*, not the git author recorded in a commit. It
does change the baseline the cost is measured against, and it means the
attribution being defended is already arbitrary.

### Prior art: this is known upstream, and unfixed

The obvious lever — cloud environments accept environment variables and
setup scripts, so set `GIT_AUTHOR_EMAIL` — has been tried by others and
does not work. It breaks GPG/SSH signature verification in web sessions,
because the environment's signing credentials are held outside the
sandbox and are bound to the identity it sets. Assume this route is
closed until proven otherwise.

The upstream record is unambiguous, and consistently stale:

| Issue | Substance | Status |
| --- | --- | --- |
| [claude-code#18715](https://github.com/anthropics/claude-code/issues/18715) | This exact problem: web-session commits attributed solely to Claude, user absent from contributor stats. Asks for an automatic `Co-authored-by` trailer | **Closed, not planned**; `stale` |
| [claude-code#65710](https://github.com/anthropics/claude-code/issues/65710) | Agent commits attributed to an *unrelated* GitHub account, which then appears in Contributors | Open, `stale` |
| [claude-code#72477](https://github.com/anthropics/claude-code/issues/72477) | `noreply@anthropic.com` resolves to no account; asks for a configurable or omitted address | Open, `stale` |
| [claude-code#65657](https://github.com/anthropics/claude-code/issues/65657), [#45137](https://github.com/anthropics/claude-code/issues/45137) | The documented `attribution.commit` setting is ignored; the built-in trailer wins | Open |
| [community#188915](https://github.com/orgs/community/discussions/188915) | A phantom "claude Claude" contributor on GitHub's side, from its own AI attribution feature | Community workaround only |

Issue #65710 is the same class of defect visible in this repo: the
`claude` account credited by our commits is a third party with no
involvement, and it sits in the Contributors list. GitHub offers a
partial mitigation of its own — repository **Settings → Code security
and analysis → AI-powered features → AI contribution attribution** — but
availability is inconsistent and it addresses GitHub's synthetic entries,
not the git author field.

Two conclusions follow. First, cloud commit attribution should be treated
as **fixed and outside our control** for planning purposes, not as a dial
to be tuned. Second, that makes the identity decision *cheaper* rather
than dearer: if cloud commit credit cannot be reclaimed by any means,
the bot identity forfeits nothing further, and the marginal cost narrows
to the PR-opened statistic alone.

What actually changes under a separate identity:

- **Lost**: PRs opened, which move to the bot. Issues too, when the
  agent files them.
- **Kept**: merge commits, because the human still clicks Merge — but
  only under the merge-commit strategy. A squash merge attributes the
  squashed commit to the branch author, so squash-merging would forfeit
  these regardless of identity. Session surface and merge strategy each
  move the graph at least as much as identity does.
- **Gained**: a review contribution per PR, because the approval gate
  makes reviewing mandatory rather than optional.

The trade is roughly one "PR opened" for one "review submitted" per unit
of work. The green squares survive; the labels on them change from
authoring to reviewing, which is a more accurate description of the work
being done. The visible cost is the repo's Contributors list, which is
commit-author based and would show the bot on top.

## Options

### Option 1 — Rulesets only, single identity

Apply a ruleset to `main`: require a PR, require status checks, block
force-push and deletion, empty bypass list. No approval requirement,
because a lone identity cannot satisfy one. The gate is the merge
button, backed by a `deny` entry for `mcp__github__merge_pull_request`,
`Bash(gh pr merge*)`, and `pull_request_review_write`.

- **Cost**: about ten minutes. No new accounts, no per-repo admin.
- **Statistics**: entirely unchanged.
- **Enforcement**: direct push to `main` becomes genuinely impossible.
  The merge gate does not — the session holds admin, so the deny rules
  are the only thing stopping a self-merge, and they are client-side.
- **Audit**: commit authorship already separates agent from human. API
  actions — PR creation, comments, merges — remain indistinguishable.

### Option 2 — Rulesets plus a bot as the connecting identity (recommended)

Create `pmgledhill102-bot`, invite it to each repo with **Write** (never
Admin), and reconnect the Claude Code GitHub integration authorising as
that account — either through the browser OAuth flow in a separate
profile, or by logging `gh` in as the bot and running `/web-setup`.
Verify with one command: `get_me` in a fresh cloud session must return
`pmgledhill102-bot` with `admin: false`.

Then the ruleset from Option 1 plus `required_approving_review_count: 1`,
which becomes possible for the first time because the PR author and the
approver are now different principals.

- **Cost**: account setup with its own email and 2FA; a collaborator
  invite per repo; the PR-opened statistic.
- **Enforcement**: Write cannot edit rulesets, so the agent provably
  cannot weaken its own guardrails. The gate is enforced by GitHub, not
  by the agent's own config file.
- **Audit**: complete separation. Every commit, PR, comment and review
  carries a distinct login.
- **Operational catch**: the GitHub connection is per-Claude-account, not
  per-repo, so cloud sessions can only reach repos the bot can see. A
  repo without the invite fails at session creation. This is a real
  friction and also the foundation of the access-control design below.
- **Note**: the local CLI is unaffected and continues to act as the human
  unless `GH_TOKEN` is pointed at the bot. Given cloud is the primary
  surface, that asymmetry is acceptable.

GitHub's terms permit one machine account alongside a personal account,
and the bot connects to the *existing* Claude account — no second
subscription.

### Option 3 — A self-owned GitHub App

Own an App with `contents: write` and `pull_requests: write` but not
`administration`, minting one-hour installation tokens.

**Rejected.** Cloud sessions cannot use it — they authenticate as the
connecting user — so it would only bind the local CLI and Actions, which
is precisely the surface that matters least. It also requires a
token-minting flow, which is the kind of extra approval machinery this
design is meant to avoid.

### Option 4 — Prose and hooks only (status quo)

**Rejected.** This is the arrangement that failed. An agent that can edit
`home/settings.json` and `home/bin/*` can edit its own constraints in the
same PR that does something else.

## Decision

Adopt **Option 2**, in two stages, so the enforcement lands before the
account work:

1. **Now**: apply the Option 1 ruleset to `main` here and across the
   estate. This is strictly additive and is worth doing whichever way
   the identity question resolves.
2. **Next**: create the bot, move the Claude connection to it, and raise
   `required_approving_review_count` to `1`.

`require_last_push_approval` stays **off** initially. Its effect with a
single human is to make all code arrive via the bot — defensible, but it
deadlocks any PR the human pushes to, and that friction should be a
deliberate later choice rather than a side effect of this ADR.

### CODEOWNERS

Adopt it, path-scoped rather than blanket. With one human, whole-repo
CODEOWNERS is redundant with a single required approval. Its value here
is narrower and real: `home/settings.json`, `home/bin/*`,
`home/skills/setup-repo/`, and `.github/workflows/` **are** the
guardrails, and changes to them warrant a stricter gate than a README
edit.

The second-order benefit is the more useful one. With code-owner review
required only on those paths, the default requirement can be *relaxed*,
letting `gh pr merge --auto` actually complete routine documentation and
skill changes on green CI while guardrail changes still stop for a
human. Today everything is gated identically, so nothing auto-merges.

Mechanics: personal repos support `@username` owners; the owner needs
write access, so the bot is never listed; the file must be on `main` to
take effect; and syntax errors silently disable rules, so the validation
view must be checked after committing.

## Access control as code

The per-repo collaborator invite in Option 2 is the point where this
either becomes a system or becomes a chore. Making it declarative is
what turns the friction into the feature: an explicit, reviewable
statement of exactly which repos the agent may touch.

`paul-context` — already the personal-tier home under ADR-0015 — gains a
registry:

```yaml
# agents/access.yaml
identity: pmgledhill102-bot
repos:
  - name: pmgledhill102/agentic-coding-config
    permission: push          # GitHub Write
    ruleset: standard
  - name: pmgledhill102/some-sandbox
    permission: push
    ruleset: relaxed
```

A scheduled workflow in `paul-context` reconciles reality against the
file: it invites, downgrades or removes the bot to match `permission`,
applies the named ruleset profile to each repo, and opens an issue on
drift. Deleting a line revokes access on the next run — the property
manual invites never have.

Two invariants make this safe, and both are load-bearing:

1. **The bot has no access to `paul-context`.** If the agent can edit the
   registry, it can grant itself anything. This is the single rule that
   the whole design rests on.
2. **The reconciler credential lives only in `paul-context`.** It needs
   `administration: write`, so it must not be reachable from any repo the
   bot can write to. Per-repo secret scoping gives this by default;
   stating it prevents a later workflow from breaking it.

The credential is a fine-grained PAT initially, and a self-owned GitHub
App if rotation becomes a nuisance. This is CI automation with no
interactive approval step, so it does not reintroduce the approval flow
rejected in Option 3.

`paul-context` being private means cloud sessions cannot read the
registry — consistent with the trade-off ADR-0015 already accepted. The
reconciler runs in Actions, so this costs nothing operationally.

## Consequences

### Positive

- The push and merge rules become facts about the repository rather than
  requests to the agent, and survive an agent that edits its own config.
- Agent and human actions separate completely in the audit trail, across
  commits, PRs, comments and reviews.
- The agent provably cannot alter its own guardrails, because Write
  cannot edit rulesets.
- Agent reach becomes a reviewable file with a working revocation path.
- CODEOWNERS makes routine auto-merge safe, which is a net *reduction*
  in friction despite being a new control.

### Negative / trade-offs

- The PR-opened statistic moves to the bot, and the Contributors list
  shows the bot on top. Reviews replace it on the graph.
- A collaborator invite is required per repo, and a missing one fails at
  session creation rather than with a clear permission error.
- Another account to hold: email, 2FA, recovery.
- Repo ownership still implies admin, so the ruleset can always be
  disabled by the human. The control is that doing so is deliberate and
  logged — prevention is not available to a sole owner.
- `paul-context` becomes materially more sensitive: it now governs access
  rather than merely recording decisions.

## Follow-on work

- `setup-repo`: replace `required_pull_request_reviews: null` and its now
  obsolete comment with the bot-aware ruleset payload
- `CODEOWNERS` for the guardrail paths, plus the relaxed default
- A protection audit script with a `--check` mode for CI drift detection
- `home/settings.json`: a `deny` block for `merge_pull_request`,
  `pull_request_review_write` and `gh pr merge`, and a `prepush-guard`
  extension covering pushes to the default branch and force-pushes

## References

- [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web)
  — GitHub authentication options; sessions act as the connecting account
- [Co-authored-by and the contribution graph](https://github.com/orgs/community/discussions/186410)
  — GitHub staff confirmation that trailers give no graph credit
- [Creating a commit with multiple authors](https://docs.github.com/en/pull-requests/committing-changes-to-your-project/creating-and-editing-commits/creating-a-commit-with-multiple-authors)
- [Troubleshooting missing contributions](https://docs.github.com/en/account-and-profile/how-tos/contribution-settings/troubleshooting-missing-contributions)
- [ADR-0015](0015-tiered-adrs.md) — tier placement for this decision
