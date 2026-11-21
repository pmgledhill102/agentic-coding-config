# Review: what the config says about Claude Code, against Claude Code today

- **Date**: 2026-11-21
- **Tracking**: [#785](https://github.com/pmgledhill102/agentic-coding-config/issues/785),
  workstream 3
- **Versions**: `claude --version` reports 2.1.330 in the sandbox this ran in;
  the newest changelog entry read was 2.1.330 (2026-11-20). The environment
  variable `CLAUDE_CODE_VERSION` in the same container says 2.1.42
- **Decisions arising**: none yet. Every row is input to the inventory in
  workstream 2

This review answers two questions. Which statements in this repo about how
Claude Code behaves are still true? Which Claude Code capabilities does the
config not use?

The Codex half of workstream 3 is not in this file yet.

## 1. Verdict up front

**Four statements are out of date and one permission rule probably never
matched.** None is dangerous. Each is a rule or a rationale that describes an
older harness.

**The with/without test the epic asks for is built in.** `claude plugin eval`
runs each case with and without a plugin and reports the difference. It takes
a plugin as its target, not an instruction file, so it measures skills
directly and policy text only once that text is packaged as one.

**Two capabilities attack the always-loaded budget directly.** Path-scoped
rules load only when a matching file is touched. `omitClaudeMd` stops a
sub-agent loading the policy at all.

**Two things the cloud delivery rests on are measured here and contradicted by
the documentation's plain reading.** Hooks and skills written into the
container's `~/.claude/` both work today. The docs describe user settings and
user skills as not carried into cloud sessions. `env-conformance` is what
stands between that gap and a silent failure.

## 2. Is each harness claim still true?

"Checked" says how far the verdict can be trusted:

- **docs**: the sentence was read on the documentation page and is quoted
- **observed**: seen directly in the session that wrote this review
- **probe**: `env-conformance` measured it in that session
- **reported**: a research sub-agent's finding that was not re-checked

| Claim | Where | Verdict | Checked |
| --- | --- | --- | --- |
| "Batch reads before edits … avoids 'file not read yet' errors" | `core.md` | **Changed.** The requirement now depends on the model | docs, observed |
| A foreground command that passes 120s "is not killed … but the result is lost" | `CLAUDE.md`, Build & Test | **Changed.** It is moved to the background and its output path is returned | docs |
| "`echo A; git status; echo B` is one string to the matcher" | `home/settings.json.md` | **No longer true.** Compound commands are split and every part must match | docs |
| `Edit(/tmp/**)` and `Edit(/private/tmp/**)` approve scratch space | `home/settings.json` | **Probably never matched.** A single leading slash is not the filesystem root | docs; not tested live |
| Waiting with `sleep N && cat <file>` is refused | `CLAUDE.md`, Build & Test | **Still true** | observed |
| `gh api` REST works on attached repos; GraphQL-backed subcommands are refused | `persist-ephemeral.md` | **Still true**, and now documented | probe, reported |
| Hooks in a container-written `~/.claude/settings.json` fire | `cloud/README.md`, ADR-0016 | **Still true, undocumented** | probe |
| Skills in a container-written `~/.claude/skills` are invoked | ADR-0016 | **Still true, undocumented** | observed |
| A setup script may write `~/.claude/CLAUDE.md` as user instructions | `cloud/README.md` | **Still true**, and the documented route | reported |
| `AGENTS.md` is read only when no `CLAUDE.md` is in scope | ADR-0023 | **Still true**, native from 2.1.277 | reported |
| PreToolUse exit 2 blocks and returns stderr; `updatedInput` rewrites input | `home/settings.json.md` | **Still true** | reported |
| `deny` rules hold in every permission mode | `home/settings.json.md` | **Still true** | reported |
| `Write(...)` rules match nothing; use `Edit(...)` | `home/settings.json.md` | **Still true** | reported |
| Setup-script requests get no injected credential; the OpenTelemetry export bypasses the proxy | `cloud/README.md` | **Still true** | reported |
| "API credentials" as the name of the environment setting | `cloud/README.md` | **Renamed** to "network secrets" | observed |
| A heredoc matches no prefix rule and prompts every time | `os-macos.md`, `env-wsl.md` | **Cannot tell** | docs silent |
| A setup script's `export` does not reach the agent | `cloud/README.md`, ADR-0016 | **Cannot tell** | docs silent |

### The four that changed

**Read before edit.** The tools reference says:

> Claude Opus 4.6, Claude Haiku 4.5, and older models always require the read.
> Newer models can edit an unread file when reading it wouldn't need a
> permission prompt and the Read tool is available.

So the rule is a no-op for a newer model in a repo it may read freely, and
still load-bearing for an older one. Telemetry agrees as far as it goes: 946
Edit calls in cloud sessions between 19 October and 20 November, none failed,
against 869 Read calls. The rule sits in the portable core, which Codex also
loads, so it cannot simply be deleted there. It can move to the Claude adapter
and be worded by model.

**The 120-second timeout.** The tools reference says:

> When a foreground command reaches its timeout without finishing, Claude Code
> moves it to the background instead of stopping it, unless the command starts
> with `sleep`.

An unattended session gives such a command 30 minutes from the move. The
project instructions say the result "is lost and has to be recovered", which
describes the earlier behaviour. Running the full gate list in the background
from the start is still the cheaper habit. A call may also ask for up to ten
minutes, which covers the ~160s bootstrap test on its own.

**Compound commands.** The permissions page says:

> The recognized command separators are `&&`, `||`, `;`, `|`, `|&`, `&`, and
> newlines. Every subcommand must be allowed for a compound command to run
> without a prompt

`home/settings.json.md` gives "one string to the matcher" as the reason the
session-lifecycle steps were moved into scripts. The scripts are still worth
having for other reasons. The stated reason is no longer the mechanism.

**`Edit(/tmp/**)`.** The permissions page says:

> A pattern like `/Users/alice/file` isn't an absolute path. The single leading
> slash anchors at the settings source, not the filesystem root. Use
> `//Users/alice/file` for absolute paths.

Both rules in `home/settings.json` use one slash. If the documentation is
right they have never granted `/tmp`. This fails closed, so the cost is a
prompt and not an exposure. It needs one live test on a workstation before
the rules are rewritten as `Edit(//tmp/**)`.

## 3. Capabilities the config does not use

Ranked by how much they bear on #785, not by general usefulness.

| # | Capability | What it is | Bears on | Checked |
| --- | --- | --- | --- | --- |
| 1 | `claude plugin eval --ablation with-without` | Runs each eval case with and without a plugin and reports the score difference. Needs 2.1.269 | Workstream 5. It is the with/without test | docs, observed |
| 2 | Path-scoped rules | A file under `.claude/rules/` or `~/.claude/rules/` with a `paths:` list loads only when a matching file is read or edited | Workstream 2. Moves shell, Terraform and GitHub guidance out of the always-loaded tier | docs |
| 3 | `omitClaudeMd` on a sub-agent | A custom sub-agent starts without the user, project and local `CLAUDE.md`. Needs 2.1.271 | Workstream 2. Every other sub-agent pays for the whole policy | docs |
| 4 | `/doctor prompt-audit` | Checks instruction files for outdated or conflicting content. Needs 2.1.283 | Workstream 2. A free first pass over the fragments | docs |
| 5 | `disable-model-invocation: true` on a skill | Removes the skill's description from context; the user types it | Workstream 2. Already noted in the `mattpocock/skills` review | reported |
| 6 | Hook `if` field | A hook runs only when a permission-style pattern matches | The three Bash guards would stop spawning on every Bash call | reported |
| 7 | Auto mode with `denyInsteadOfPrompting` | A classifier decides; a block becomes a denial, not a prompt | Workstream 4. Could shrink the Bash allowlist on a workstation | reported |
| 8 | Dynamic workflows | A script runs many agents with checked outputs and resumes after a stop | Unattended multi-hour runs; what `bundle-issues` does by hand | observed |
| 9 | Auto-fix for pull requests | A cloud session subscribes to CI failures and review comments | Could replace the PR-checks wait hook | reported |
| 10 | Auto memory | Claude keeps its own notes per repo | Overlaps what the retro writes into policy; one of them should own each lesson | reported |

### Notes on the first three

**`claude plugin eval`.** The help text in the sandbox reads:

> Run a no-plugin baseline arm and report the score delta (none |
> with-without; default: with-without whenever a plugin resolves)

Its target is a plugin directory, a case file or an installed plugin, and the
help says a skills directory resolves as one. An instruction file is not a
target. So:

- a skill can be tested as it stands
- a policy rule can be tested by loading it as a one-skill plugin for the
  trial, which measures the rule's text but not its always-loaded position
- up to eight runs go in parallel, all on one credential and one rate limit

This replaces the third-party harnesses named in `ideas/skill-evals.md`.

**Path-scoped rules.** The memory page says a path-scoped rule "loads when
Claude uses the Read, Write, or Edit tool on a matching file", and that
personal rules in `~/.claude/rules/` "apply to every project on your
machine". It does not say outright that `paths:` works at user level, and
nothing says whether a cloud session loads `~/.claude/rules/`. Both need a
probe before any fragment moves. A repo-level rules file would also cut
against ADR-0016, which keeps agent config out of project repos.

**`omitClaudeMd`.** The sub-agents page says Explore and Plan already start
without `CLAUDE.md`, and that other built-in and custom sub-agents load it
unless the field is set. Sub-agents ran in 22 of 131 cloud sessions in the
telemetry window, so the saving today is modest. It grows with every move
towards delegated or parallel work.

## 4. What this changes in #785

- **Workstream 2** gains three destinations that are not deletion: a
  path-scoped rule, a typed-only skill, and a sub-agent that omits the policy.
- **Workstream 5** has its tool. The open design question is how to test
  always-loaded text, since the eval targets plugins.
- **Workstream 6** has a version signal problem. A release-triggered re-check
  needs to know which version is running, and the CLI and the environment
  variable in one container disagree.
- **`env-conformance`** should gain a probe for each "cannot tell" row that a
  script can settle: the `Edit(//tmp/**)` anchor, `~/.claude/rules/` in a
  cloud session, and a setup script's `export`.

## 5. Method and limits

- A research sub-agent read the policy fragments, `home/settings.json.md`,
  `cloud/README.md` and ADR-0016 and ADR-0023, then the documentation at
  `code.claude.com/docs` and the first part of the changelog. It had no shell.
- Seven of its claims were then re-read on the documentation pages and are
  quoted above. `claude plugin eval --help` and `env-conformance` were run in
  the sandbox (19 probes passed, none failed).
- Rows marked **reported** rest on the sub-agent alone.
- The changelog is 1.4 MB and only its first 100,000 characters were read, so
  version numbers for older changes may be missing.
- Nothing here was tested on a workstation or under Codex.
- Telemetry figures cover cloud sessions from 19 October to 20 November 2026.
