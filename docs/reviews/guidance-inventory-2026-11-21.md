# Inventory: every always-loaded rule, with a proposed disposition

- **Date**: 2026-11-21
- **Tracking**: [#785](https://github.com/pmgledhill102/agentic-coding-config/issues/785),
  workstream 2
- **Status**: a proposal. Nothing in `context/` has been changed. Each
  disposition is a recommendation for the owner to accept, change or refuse
- **Inputs**: the rule classification from workstream 1, the harness review in
  [`harness-capability-review-2026-11-21.md`](harness-capability-review-2026-11-21.md),
  and the four dead-weight tests from
  [`pocock-skills-review-2026-11-20.md`](pocock-skills-review-2026-11-20.md)

This inventory answers one question for each of the 93 rules in
`context/fragments/`: does it still earn a place in every turn of every
session?

## 1. Verdict up front

**About half the always-loaded text can leave without losing a rule.** The
cloud-sandbox profile is about 4,900 words. The proposals below remove an
estimated 2,300, before any with/without test has run. Most of that is
rationale, not rules: a rule stays as one line and its reasoning moves to the
ADR or doc that already holds it.

**Seven rules are the owner's process decisions and are not mine to dispose
of.** They go to workstream 4, the risk-tier ADR.

**Eight rules should be tested, not argued about.** Most correct model
behaviour, and only a with/without run says whether today's models still need
them. The test list in section 7 has ten runs, because two rules with another
disposition are worth measuring as well.

**Four rules that recur most are not working as text.** The session record
shows the same mistake repeating about ten times after each rule existed. The
proposal for those is a check, a shorter rule, or both.

| Disposition | Rules | Meaning |
| --- | --- | --- |
| Keep | 35 | Still true, short, and doing work |
| Shrink | 16 | Keep the rule, move the rationale out |
| Move | 16 | Load only when relevant, or only on the surface it is true of |
| Check | 3 | Enforce with a hook or setting; text becomes one line |
| Test | 8 | Run with and without before deciding |
| Decide | 7 | An owner decision, for workstream 4 |
| Fix | 5 | The statement is now wrong |
| Delete | 4 | Nothing would be lost |

That is 94 rows: the 93 rules, plus one table in the Claude adapter that is
not a rule but costs about 120 words.

## 2. How each rule was judged

Each rule has a **kind**, from workstream 1:

- **decision**: the owner's convention
- **platform**: a fact about GitHub, a cloud, an OS, a CLI or the sandbox
- **harness**: a workaround for the agent harness
- **model**: a correction to a mistake the model made

Each was then put to the four dead-weight tests:

- **No-op**: the model does it anyway
- **Cache**: one command would show the same thing
- **Sediment**: it describes a world that has moved on
- **Duplication**: the same meaning is stated, or enforced, somewhere else

Evidence comes from three places: the session record (127 journal entries,
kept privately), cloud telemetry from 19 October to 20 November, and the
harness review. "Recurs" means the same mistake appears in later sessions
after the rule existed. "Never credited" means no session records the rule
preventing anything.

Words are counted in `context/fragments/core.md` and are approximate.

## 3. The core fragment

### Which repos this applies to (442 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| C1 | Ownership is read from the origin remote; match owner and repo, not a prefix | decision | Shrink | The two-URL-forms explanation is rationale |
| C2 | The owner set is one account; one named org is not mine | decision | Keep | A real boundary, and it was corrected by the owner once |
| C3 | One named repo in that org is mine | decision | Keep | Short |
| C4 | In someone else's repo, their conventions win | decision | Shrink | Likely a no-op for the rule itself; keep one line |
| C5 | Forks: workflow applies, repo standards do not | decision | Move | Rare. Belongs with the repo-standards doc, behind a pointer |
| C6 | A repo's own committed instructions override this | decision | Keep | Short, and it defines precedence |
| C7 | When ownership is unclear, ask | model | Test | No origin found. A candidate no-op |

### Git workflow (479 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| C8 | Feature branch and a pull request for every change | decision | Decide | Workstream 4 |
| C9 | Journal entries go straight to the default branch | decision | Move | Only the `retrospective` skill writes them, and its body already says so. Duplication |
| C10 | Merge commits only; squash and rebase disabled | decision | Shrink | 208 words. The repository setting enforces it, so an agent cannot break it. One line and a pointer to the standard |
| C11 | Watch CI and make sure it passes | decision | Keep | Short |
| C12 | Do not merge your own pull requests | decision | Decide | Workstream 4. Every merge is recorded under one account, so nothing can tell whether it was followed |
| C13 | Check the pull request is still open before pushing or asserting its state | model | Check | Recurs about ten times. The pre-push guard has caught it twice; extend the guard and cut the text to one line |
| C14 | Ask whether related changes share a branch | decision | Decide | Workstream 4. A cloud session has one branch, which already forces the answer |

### Work tracking (183 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| C15 | Create an issue before starting work | decision | Decide | Workstream 4 |
| C16 | Hierarchy by sub-issues, dependencies by blocked-by | decision | Move | Restates `docs/github-issues-workflow.md`, which the rule already links |
| C17 | Priority and type labels; issue types are org-only | decision | Move | Same |
| C18 | One repo's own label taxonomy wins | decision | Move | Covered by C6 |
| C19 | A read-back of just-written state lags; wait before diagnosing | platform | Shrink | 110 words for a rule that rarely recurs. Keep the instruction and one example |
| C20 | Never issue search for anything time-sensitive; deduplicate against the full list | platform | Shrink | Still recurs as duplicate issues. Merge with PC3, which says the same |

### Decision records (197 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| C21 | Three ADR tiers, placement by scope, explicit deviation | decision | Move | Matters only while writing an ADR. Two lines and the URL stay; the rest loads with `adrs/` |

### Cross-repo work (276 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| C22 | Never edit a repo other than the one the session works in | decision | Keep | A boundary that held throughout the record |
| C23 | File a detailed issue in the target repo | decision | Shrink | Keep the definition of "detailed"; drop the reassurance |
| C24 | Read the other repo, at origin's head, before asserting how it behaves | model | Test | The most-recurring rule in the record. It has been reworded three times without effect. Test first, then shrink to one sentence whatever the result |
| C25 | Say what you filed | decision | Keep | Short |

### Changing agent config, and commit style (214 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| C26 | Request config changes by issue; never edit generated config | decision | Shrink | Keep the rule and the reason in one sentence each |
| C27 | Commit paragraphs through repeated `-m` flags | harness | Move | Exists to avoid heredoc prompts on a workstation. Sediment in a sandbox, where nothing prompts |
| C28 | Use a generic co-author name even when a reminder names a model | harness | Check | A commit-message hook can enforce it; the reminder it contradicts arrives every session |
| C29 | What a public artefact may say is ADR-0022's table | decision | Check | #760 already proposes enforcing it at write time |
| C30 | Prefer a file over inline for multi-line content | harness | Move | Same reason as C27, and `os-macos.md` already states it |

### Process guidelines (819 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| C31 | Three strikes, then question the approach | model | Test | No origin found, and never credited. The one mention says it did not fire |
| C32 | Preview an irreversible batch, then stop | model | Shrink | 194 words. Cheap insurance against a rare, costly mistake, so it stays; the classifier in auto mode now blocks much of the same. Keep about 50 words |
| C33 | Mask by allowlist, never by denylist | model | Keep | Short and concrete, and the mistake stopped recurring |
| C34 | When a check reports nothing, prove it could have spoken | model | Shrink | Working, and increasingly credited. Four examples can be one |
| C35 | Check release notes before upgrading a CLI | model | Delete | No origin, never credited, and a no-op candidate |
| C36 | Lint before pushing | decision | Shrink | The pre-commit hook enforces it. One line for when the hook is absent |
| C37 | Native binaries over package runners | harness | Test | Unclear origin; the sandbox shims now route these calls anyway |
| C38 | Single-concern pull requests | decision | Decide | Workstream 4. In tension with one branch per cloud session and with bundle issues |
| C39a | Only claim "stacked on" when it is literally true | model | Move | Matters only when stacking. Into a skill body or a scoped rule |
| C39b | A stacked pull request stays a draft; re-parenting behaviour | platform | Move | Same |
| C40 | Batch reads before edits | harness | Fix | The harness now requires a prior read only on older models. Move to the Claude adapter and word it by model, or delete |
| C41a | Always create a tracking issue, even for a one-file fix | decision | Decide | Workstream 4 |
| C41b | A doc-sized correction is fixed in the session, not filed | decision | Decide | Workstream 4; it is the existing exception to C41a |
| C42 | A fetch blocked by a 403: go to `curl` and `pandoc` | harness | Keep | Already cut to one line |

C41b is the existing exception to C41a, so the two are one decision.

### Shell scripts (466 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| C43 | Target POSIX sh | platform | Move | Shellcheck by shebang enforces it in CI and pre-commit. Load with shell files only |
| C44 | Where BSD and GNU differ, try both | platform | Move | Same |
| C45 | Bash, if required, must run on 3.2 | platform | Move | Same |
| C46 | Pass the non-interactive flag; an agent has no tty | harness | Shrink | Still recurs. Keep the rule and the symptom |
| C47 | Verify CLI flags before using or recommending them | model | Test | Recurs. The clearest candidate for a with/without run |
| C48 | Multi-step probe loops go in a script file | platform | Move | Recurs about ten times, each logged as non-compliance. Its stated reason is the interactive shell, which is zsh on a workstation and bash in a sandbox. Move to the surface it is true of |
| C49 | Raw strings when patching through a Python heredoc | model | Test | Recurs. Short enough to keep if the test says it helps |

## 4. The other fragments

### Ephemeral-first (566 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| E1 | Environment as a committed, idempotent script | decision | Shrink | No incident produced the fragment. Hand installs still recur, so the rule stays; the essay goes to the ADR |
| E2 | The repo is the default durable output | decision | Shrink | Same. Uncommitted work lost to a reclaimed container is recorded and was costly |
| E3 | Durable storage is granted, never assumed | decision | Shrink | Same |
| E4 | Remote Terraform state from the first init | decision | Move | Load with Terraform files |

Four principles at a line each, plus the closing question, is about 150 words.

### Ubuntu and the cloud sandbox (518 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| U1 | System Python refuses `pip install` | platform | Test | A no-op candidate |
| U2 | `apt-get` needs `-y` | platform | Delete | C46 says it |
| P1 | The launcher also writes to `~/.claude` | platform | Keep | |
| P3 | A session may start in the parent of its repos; read them first | model | Keep | Recent, concrete, one recurrence |
| P4 | Request brokered cloud access before asserting live state | model | Keep | |
| P5 | Delivered skills are the whole set | decision | Keep | |
| P6 | Docker builds go through the proxy | platform | Keep | One line and a skill pointer already |
| P7 | A blocked host is not a dead end | platform | Keep | Used twice in the session that wrote this |
| P8 | Cloud credentials may be a literal placeholder | platform | Keep | Stopped recurring |
| P9 | Which `gh` paths work | platform | Keep | Verified today by `env-conformance` and now documented by the vendor |
| P10 | A denied repo attach is the owner's call | harness | Keep | The friction it describes is current |
| P11 | Every GitHub request carries credentials | platform | Keep | Stopped recurring |
| P12 | A remote branch delete reports success and deletes nothing | platform | Keep | |
| P13 | Helpers report when `gh` was unavailable | platform | Keep | |
| P14 | Judge the remote-session tools by what a call returns | harness | Keep | Needs a probe: is the approval-binding bug still present? |

The sandbox fragment is the model for the rest: short, concrete facts, each
probed weekly. It is also where the two rules whose problem stopped recurring
live.

### Workstation fragments (982 words; not loaded in a sandbox)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| M1 to M3 | zsh behaviours and shell aliases | platform | Keep | True of the surface they load on |
| M4 | `/tmp` resolves to `/private/tmp`, so rules carry both spellings | harness | Fix | Both rules use a single leading slash, which the permissions docs say is not the filesystem root. One live test, then rewrite |
| M5 | No heredocs: they match no prefix rule | harness | Keep | Needs a probe. Compound commands are now split; heredocs are undocumented |
| D1 to D3 | `~/.claude` is chezmoi-managed; refresh period; pruning | platform | Keep | |
| D4 | The chezmoi dry-run check | platform | Delete | The project instructions say this gate never applied to this repo |
| W1 | On WSL, stay on the Linux filesystem | decision | Keep | A hook enforces it |

### Claude adapter (634 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| PC1 | Prefer the GitHub MCP tools over `gh` | harness | Shrink | Keep the preference; the tool-name list is a cache of the tool list |
| PC2 | `list_issues` must be given `fields` | harness | Keep | Still true and still costly when forgotten |
| PC3 | One page is a recency check, not a dedup pass | model | Shrink | Merge with C20 |
| PC4 | `list_pull_requests` takes `fields` | harness | Keep | |
| PC5 | The two tools spell `state` differently | harness | Keep | |
| PC6 | `get_sub_issues` has no field filter | harness | Keep | |
| PC7 | The pending-review workflow | harness | Delete | The GitHub MCP server's own instructions state it. Duplication |
| PC8 | `gh` commands in a skill are illustrative | model | Keep | Or remove the literal `gh` commands from the skills, and then this goes too |
| PC9 | Both routes are auto-approved; keep `--repo` first | harness | Move | A workstation permission detail. Sediment in a sandbox |
| — | "How the portable rules map to these tools" table | harness | Test | About 120 words. A cache of the tool list, and a no-op candidate |

### Codex adapter (230 words)

| ID | Rule | Kind | Proposed | Why |
| --- | --- | --- | --- | --- |
| X1 | Codex reads one `AGENTS.md` and nothing else | harness | Fix | It layers a global file and one per directory |
| X2 | Skills are read from `~/.agents/skills/` | harness | Keep | |
| X3 | Use the `gh` CLI | harness | Fix | The bootstrap installs none for the Codex cloud profile |
| X4 | A hook authored once works on both | harness | Fix | True of the JSON shape only |

## 5. What this frees

Estimated for the cloud-sandbox profile, in words:

| Section | Now | After | Mostly from |
| --- | --- | --- | --- |
| Which repos this applies to | 442 | 200 | C1, C4, C5 |
| Git workflow | 479 | 200 | C10, C9 |
| Work tracking | 183 | 90 | C16 to C19 |
| Decision records | 197 | 40 | C21 |
| Cross-repo work | 276 | 170 | C23, C24 |
| Commit style and config changes | 214 | 110 | C27, C30 |
| Process guidelines | 819 | 420 | C32, C39, C34 |
| Shell scripts | 466 | 120 | C43 to C45, C48 |
| Ephemeral-first | 566 | 180 | The essay around E1 to E4 |
| Claude adapter | 634 | 380 | The mapping table, PC7, PC9 |
| Ubuntu and sandbox | 518 | 500 | U2 |
| **Total** | **4,794** | **2,410** | |

That is roughly a 328-line profile becoming 170 to 190 lines. The estimate
assumes every Move finds a home. It does not count the eight rules under
Test, which could free more, or the seven under Decide.

## 6. What has to be true first

**Three probes.** A Move is only safe if the destination loads.

1. Does a cloud session load `~/.claude/rules/*.md`, and does `paths:` work
   there? The docs say personal rules apply to every project and do not say
   whether a sandbox reads them. If not, the Move rows fall back to a skill
   body or a linked doc.
2. Does `Edit(//tmp/**)` grant what `Edit(/tmp/**)` was meant to? One test
   on a workstation.
3. Does a heredoc still prompt on a workstation? The docs are silent.

**One decision.** Moving a rule out of the portable core and into a
Claude-only rules file costs Codex that rule. For each Move, either Codex
gets the same text in its global `AGENTS.md`, or the rule is one Codex does
not need.

## 7. The test list

Ten with/without runs, in priority order: the eight rules marked Test, plus
C13 and C34, whose dispositions do not wait on the result. Each needs a trap
scenario, because these mistakes are rare in ordinary work.

| # | Rule | The trap |
| --- | --- | --- |
| 1 | C24 read before asserting | Ask how a second repo behaves, with a stale description of it in the first |
| 2 | C47 verify CLI flags | A task that invites a plausible flag that does not exist |
| 3 | C13 pull request still open | A branch whose pull request merged between two prompts |
| 4 | C49 raw strings in heredocs | Patch a file whose source holds an escaped newline |
| 5 | C31 three strikes | A bug whose first three obvious fixes all fail |
| 6 | C7 ask when ownership is unclear | A repo with no origin remote |
| 7 | U1 system Python | A task that wants a package on Ubuntu 24.04 |
| 8 | C37 native binaries | A lint task where the tool is on PATH |
| 9 | The adapter's mapping table | A GitHub task with the table removed |
| 10 | C34 prove the check can speak | A search that returns nothing because the pattern is wrong |

`claude plugin eval` runs each case with and without a plugin and reports the
difference. Each rule would be packaged as a one-skill plugin for its trial.
That measures the rule's text and not its always-loaded position, which is
the one thing this method cannot test.

## 8. Skills

Not judged here. The telemetry digest records that a skill was activated and
not which one, so there is no base rate per skill yet (#788). Two things can
be said without it:

- The 15 `setup-*` skills are typed by the owner a few times a year. Setting
  `disable-model-invocation: true` on them removes their descriptions from
  every workstation session. A sandbox does not load them at all.
- `retrospective` cannot be typed-only, because `end-session` invokes it.

## 9. Method and limits

- The rule list and each rule's kind come from a research sub-agent that read
  all nine fragments and the full session record. I checked three of its
  quotes. The dispositions are mine.
- "Recurs" and "never credited" rest on that record. It was written under the
  models of its day and names the model once in 127 entries, so it shows that
  a rule failed to prevent a mistake, not that today's model would make it.
- Word savings are estimates from the section totals, not from a rewritten
  fragment.
- Nothing was run with and without. Every "no-op candidate" is a hypothesis.
