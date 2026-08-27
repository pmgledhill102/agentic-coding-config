# agentic-coding-config

Agent configuration: slash commands, hooks, settings, MCP, and the helper
executables they drive.

It reaches an agent by **two delivery channels**, and which one applies
depends on where the session is running:

| Channel | Surface | Mechanism |
| --- | --- | --- |
| [chezmoi external][chezmoi-externals] | local machines | `home/` mounts at `~/.claude/`, via [dotfiles][dotfiles] |
| network fetch | cloud sandboxes | `cloud/bootstrap.sh`, run by the environment's setup script |

The second exists because a cloud session starts empty and reads **only the
project repo's `.claude/`** — nothing from `~/.claude/` is transferred, and
there is no machine to run chezmoi on. See
[`cloud/README.md`](cloud/README.md) for the per-environment setup and
[ADR-0016](adrs/0016-capability-delivery-principles.md) for why the substance
lives in a fetched script rather than in the environment's setup field.

## The cloud channel

An environment's setup script carries one line — a `curl … | sh` naming a ref
and a profile — and everything of substance stays in `cloud/bootstrap.sh`,
versioned here. What it installs is a **composed profile**, not this repo's
`home/`: `profiles/claude-cloud-sandbox/` and `profiles/codex-cloud-sandbox/`
are built from the same fragments as the workstation's `home/`, with the
sections that differ by surface swapped out. That is the point of the split —
a sandbox is told about the machine it is actually on.

### What each channel can and cannot carry

| Content | chezmoi | `bootstrap.sh` |
| --- | :-: | :-: |
| `skills/` | yes | yes, a named whitelist per profile |
| `commands/` | `gcp-credentials` only (#313) | no — a skill registers the same `/name` |
| `bin/` helpers | yes, at `~/.claude/bin/` | yes, same path |
| Policy prose (`AGENTS.md`, `CLAUDE.md`) | yes | yes, the profile's composition |
| Hooks | yes, via `settings.json` | yes — `--with-hooks` merges the same block |
| Permission allowlist (`settings.json`) | yes | **no** |

The last row is structural: **permissions travel only in a repo's own
`.claude/settings.json`**, which is the one place a cloud session reads them
from. No delivery channel can carry them, which is why `/setup-common` raises
the allowlist as a per-repo decision rather than stamping one.

### There was a third channel, and it was withdrawn

For a while this repo was also a Claude Code plugin marketplace: `home/`
doubled as the plugin root, and a project repo opted in with
`extraKnownMarketplaces` + `enabledPlugins` in its own `.claude/settings.json`.
It was withdrawn in [#312][issue-312] after `dotfiles` declined to adopt it
([dotfiles#392][dotfiles-392], and the consequences here in [#311][issue-311]).

The deciding reason is worth keeping, because it is a property of this repo
rather than a preference: the marketplace declared `"source": "./home"`, and
`home/` is the `claude-workstation` composition. A plugin could therefore only
ever ship workstation-composed context — so using it for cloud sessions meant
either telling a sandbox it was a laptop, or publishing one plugin per profile,
which is more machinery than the `bootstrap.sh --profile` line it replaced.

What went with it: the two manifests, `home/hooks/hooks.json`, and
`home/bin/plugin-hook-dispatch`. The hooks themselves were never plugin-only —
`home/settings.json` declares them for a workstation and `bootstrap.sh
--with-hooks` merges that same block into a sandbox, so the dispatcher that
kept a plugin-enabled machine from running each hook twice had nothing left to
stand down from. `home/settings.json.md` carries the per-hook detail.

[chezmoi-externals]: https://www.chezmoi.io/reference/special-files-and-directories/chezmoiexternal-format/
[dotfiles]: https://github.com/pmgledhill102/dotfiles
[dotfiles-external]: https://github.com/pmgledhill102/dotfiles/blob/main/home/.chezmoiexternal.toml.tmpl
[dotfiles#389]: https://github.com/pmgledhill102/dotfiles/issues/389

## How this gets onto your machine

This repo's `home/` subdirectory is mounted at `~/.claude/`. The wiring
lives in `dotfiles`, in
[`home/.chezmoiexternal.toml.tmpl`][dotfiles-external]: an `archive`
external that deploys this repo's `home/**` to `~/.claude/`, **on
`personal` machines only** ([dotfiles#389]). Work machines get no
`~/.claude/` from here.

That file is the source of truth and is deliberately not quoted here. A
copy drifts — this one did, silently, when the personal-only gating was
added.

`chezmoi apply` (or `dotup`) downloads the archive, strips the
`agentic-coding-config-main/home/` prefix, and includes only files under
that path. The result: contents of `home/` end up at `~/.claude/`,
nothing else.

**Why an `archive` external instead of `git-repo`:** `git-repo` externals
mount the entire repo tree at the target with no filtering — `.git/`,
`docs/`, README, ADRs, all of it. `archive` externals support `include`
glob patterns and `stripComponents`, which lets us deploy only the files
that should live in `~/.claude/`. The trade-off is that `archive`
re-downloads on each refresh (vs `git-repo`'s incremental fetch); for a
repo this small that's fine.

**One-line mental model:** files under **`home/`** in this repo map
directly to `~/.claude/`. So `home/skills/foo/SKILL.md` →
`~/.claude/skills/foo/SKILL.md`, `home/settings.json` → `~/.claude/settings.json`.
Files at the repo root (`README.md`, `adrs/`, etc.) are repo-meta and
don't deploy.

History before 2026-05-03 is preserved here from the original `dotfiles`
location at `home/dot_claude/` via `git filter-repo`. Older commit
messages still reference that path; that's expected. The 2026-05-03
restructure that introduced `home/` is on top of that history.

## Layout

```text
.
├── README.md                  # repo-meta: this file
├── CLAUDE.md, AGENTS.md       # repo-meta: project instructions for working ON this repo
├── adrs/                      # repo-meta: architecture decisions
├── docs/                      # repo-meta: workflow docs and runbooks
├── .github/, .pre-commit-config.yaml, .markdownlint.yaml, .gitignore
├── tests/                     # repo-meta: behavioural tests for home/bin/
├── context/                   # repo-meta: the SOURCE for everything marked GENERATED below
│   ├── manifest.json          #   which fragments compose into which output
│   ├── fragments/             #   policy fragments (core, provider, environment)
│   └── skills/                #   skill-body fragments, one dir per composed skill
├── profiles/                  # repo-meta: composed artefacts for non-workstation surfaces
│   └── <profile>/             #   AGENTS.md, CLAUDE.md, skills/ — fetched by cloud/bootstrap.sh
├── cloud/                     # ← fetched over the network into cloud sandboxes
│   ├── bootstrap.sh           #   installs the helper + skill into a container
│   └── README.md              #   per-environment setup (script, domains, vars)
└── home/                      # ← mounts at ~/.claude/
    ├── AGENTS.md              → ~/.claude/AGENTS.md  (GENERATED — composed from context/fragments/)
    ├── CLAUDE.md              → ~/.claude/CLAUDE.md  (GENERATED — composed from context/fragments/)
    ├── settings.json          → ~/.claude/settings.json
    ├── settings.json.md       → ~/.claude/settings.json.md  (annotated companion, kept alongside)
    ├── commands/              → ~/.claude/commands/  (gcp-credentials only; the twins retired in #313)
    ├── skills/                → ~/.claude/skills/    (Agent Skills — provider-neutral, the surviving form)
    └── bin/                   → ~/.claude/bin/  (helper executables)
```

Anything with a `GENERATED` banner at the top of the file is composed by
`python3 tests/compose-context.py --write` and verified in CI — edit the
fragment, not the artefact. That now covers the two session skills as well as
the policy files: `start-session` and `end-session` ship a workstation body and
a cloud-sandbox body composed from one shared fragment set, so the sandbox text
calls the GitHub MCP server where the workstation text reads what `gh` put in
the gather output ([ADR-0018](adrs/0018-composing-agent-context-per-surface.md)).

## Design principle

When linting, formatting, and security tools are configured, they become
the enforcement mechanism. Claude Code doesn't need to *know* your
standards — it just sees failures and fixes them.

This configuration separates **one-time setup** from **ongoing
enforcement**, keeping context costs low:

| Concern | Solution | Context Cost |
| --- | --- | --- |
| Setting up a new project | Slash commands (`/setup-python`) | Loaded only when invoked |
| Enforcing standards during coding | Hooks that run tools automatically | Zero — tool output is the context |
| High-level policy | Lean CLAUDE.md | ~20-30 lines |

## Enforcement layers

Checks are enforced at three layers, from most authoritative to most
immediate. Higher layers are always-on and catch everything; lower layers
are optional optimisations that provide faster feedback.

### Layer 1: CI (always enforced)

CI runs on every push/PR. This is the **source of truth** — nothing merges
without passing. Each `/setup-*` slash command includes a CI workflow
snippet for the relevant language. The `/setup-common` command also
installs a Dependabot auto-merge workflow that approves and squash-merges
Dependabot PRs once CI passes.

### Layer 2: Git pre-commit hooks

Pre-commit hooks run the same checks locally before code leaves the
developer's machine. They catch issues earlier than CI and reduce
round-trips. The `/setup-common` command installs the
[pre-commit](https://pre-commit.com/) framework, and each language command
registers its tools into it.

### Layer 3: Claude Code hooks (optional optimisation)

Claude Code hooks provide **immediate feedback during editing**. Only use
these for tools that are fast, deterministic, and auto-fix — so Claude
doesn't waste turns on formatting.

**Good candidates for file-level hooks (PostToolUse):**

- Formatters in fix mode (ruff format, prettier, rustfmt, gofmt)
- Fast linters with auto-fix (ruff check --fix, eslint --fix)

**Keep at pre-commit / CI only:**

- Type checkers (mypy, pyright, tsc) — need full project context
- Security scanners (bandit, trivy) — slow, project-wide
- Complex linters (golangci-lint with many checks) — too slow per-file

## Tooling matrix

Each `/setup-*` slash command configures the tools listed below. All
commands are **additive and composable** — run `/setup-common` first for
the foundation, then stack any combination.

| Language | Formatting | Linting | Type Checking | Security | Deps Audit | Dependabot |
| --- | --- | --- | --- | --- | --- | --- |
| **Common** | — | — | — | gitleaks | — | github-actions |
| **Markdown** | prettier | markdownlint-cli2 | — | — | — | — |
| **Shell** | shfmt | shellcheck | — | — | — | — |
| **Containers** | — | hadolint | — | trivy | — | docker |
| **Terraform** | terraform fmt | tflint, terraform validate | — | tfsec, checkov | — | terraform |
| **Go** | gofmt / goimports | golangci-lint | — | — | govulncheck | gomod |
| **Python** | ruff | ruff | mypy / pyright | bandit | — | pip |
| **.NET / C#** | dotnet format | Roslyn analysers | — | SecurityCodeScan | dotnet outdated | nuget |
| **Rust** | rustfmt | clippy | — | — | cargo-audit, cargo-deny | cargo |
| **Java** | google-java-format / spotless | checkstyle, SpotBugs, PMD | — | — | OWASP dependency-check | maven |
| **Ruby** | rubocop | rubocop | — | brakeman | bundler-audit | bundler |
| **PHP** | PHP-CS-Fixer / PHP_CodeSniffer | PHPStan / Psalm | — | — | composer audit | composer |
| **Node.js** | prettier | eslint | — | — | npm audit | npm |
| **TypeScript** | prettier | eslint + typescript-eslint | tsc --noEmit | — | npm audit | npm |

### Which layer runs what

| Tool category | CI | Pre-commit | Claude hook |
| --- | :-: | :-: | :-: |
| Formatters | yes | yes | yes (auto-fix on write) |
| Fast linters | yes | yes | optional (auto-fix on write) |
| Type checkers | yes | yes | no |
| Security scanners | yes | yes | no |
| Dependency audits | yes | no | no |

## What deploys vs what doesn't

The archive external's `include` pattern means **only `home/**` deploys via
chezmoi**. Everything at the repo root (this `README.md`, `adrs/`, `docs/`,
`.github/`, `.pre-commit-config.yaml`, `.markdownlint.yaml`, `.gitignore`,
the project-level `CLAUDE.md` and `AGENTS.md`) stays in the
repo and never lands at `~/.claude/`. No `.chezmoiignore` needed for these
— the archive filter handles it cleanly.

**`cloud/` is the exception that proves the rule.** It is excluded from the
chezmoi external like everything else outside `home/`, and it is not
repo-meta either: it is fetched over the network by a cloud environment's
setup script and executed inside the container. So it never reaches
`~/.claude/` on a laptop, and it is the only directory here that runs
somewhere this repo is not checked out.

That is also why CI shellchecks `cloud/` separately: code piped to a shell in
every sandbox is the code most in need of linting, not the least.

### Deleting a file here does not delete it on machines

chezmoi only **adds and updates** target files. Delete
`home/skills/foo/SKILL.md` and `~/.claude/skills/foo/SKILL.md` survives on
every machine that ever applied a version containing it — and Claude Code goes
on listing `/foo` as available. This bit us with the retired `bd-*` commands
([#125][issue-125]), and it is why retiring the `home/commands/` twins
([#313][issue-313]) meant 20 list entries rather than 20 deletions.

Two things follow, both non-obvious:

- **A `run_onchange_` script in `home/` will not work.** Archive
  externals are extracted to the target path verbatim; their filenames
  are *not* parsed for chezmoi attribute prefixes. That's why `exact`,
  `executable`, `private` and `readonly` exist as *fields on the
  external declaration* — they add the attribute the filename can't
  carry. A file named `home/run_onchange_cleanup.sh` deploys as a
  literal `~/.claude/run_onchange_cleanup.sh` and never executes.
- **The mechanism is an explicit retired-paths list**, not `exact = true`.
  Setting `exact` on an archive external makes chezmoi delete any target
  entry not present in the archive — which would also delete files added
  by hand on one machine that nobody remembers. (And `exact` on
  `.claude` itself would delete Claude Code's own runtime state:
  `projects/`, `todos/`, `plugins/`, `history.jsonl`,
  `settings.local.json`.) A list is more tiresome to maintain, but its
  blast radius is exactly what's written down.

### Retiring a file

Two files here do the work, so a retirement is a **single-repo change**:

| File | Role |
| --- | --- |
| `home/retired-paths` | The list. One `~/.claude/`-relative path per line |
| `home/bin/claude-prune-retired` | Reads the list, removes each path. Idempotent, refuses absolute paths and `..` |

So: **delete the file from `home/`, add its path to `home/retired-paths`,
same PR.** CI fails if an entry still exists in `home/`, so a premature
or mistyped entry can't ship. `dotfiles` invokes
`~/.claude/bin/claude-prune-retired` after each `chezmoi apply`
([dotfiles#371][dotfiles-371]) — that's the only wiring it needs, and it
never has to change again.

Entries are permanent: a machine that hasn't been applied to in a year
still needs them.

### Undeploying a file, which is not the same as retiring it

A path can need to stay in `home/` for some reason other than being deployed,
while still having to leave `~/.claude/` on machines that already have it —
because chezmoi never deletes a target it has stopped managing. Such a path
cannot be deleted from `home/` the way a retired file is. Same pruner, opposite
precondition.

`home/retired-paths` therefore has two sections, split by an `UNDEPLOYED`
marker line:

| Section | Meaning | CI asserts |
| --- | --- | --- |
| Above the marker | Retired — gone from `home/`, gone from machines | the path is **absent** from `home/` |
| Below the marker | Undeployed — still needed in `home/`, chezmoi no longer delivers it | the path is **present** in `home/` |

The inversion is the guard: an entry on the wrong side fails the build, so
neither section can quietly absorb the other's mistakes. `tests/retired-paths.sh`
is the validator and runs in CI; `tests/retired-paths-test.sh` checks the
validator against both mirror-image mistakes, because the real list is empty
below the marker and so exercises neither branch on its own.

**The undeployed section is empty.** The case that created it was `home/`
doubling as the plugin root: a path moving to the plugin channel could not be
deleted from `home/` without removing it from the plugin too. That channel was
withdrawn ([#312][issue-312] — see "There was a third channel" above), so the
case is gone and no other has appeared. The mechanism is kept because the
distinction is real and the inverted assertion is what makes it safe.

There is a second reason nothing is queued for it. An entry is only correct
once the chezmoi external has stopped deploying that path — a change to the
`include` filter in `dotfiles`, which this repo cannot make and which
`dotfiles` has decided not to make ([dotfiles#392][dotfiles-392], closed as not
planned; the consequences here are [#311][issue-311]). List a path while
chezmoi still deploys it and every `chezmoi apply` writes the file, then the
post-apply pruner deletes it again: convergent, but churn masquerading as
working.

### What chezmoi deploys, and what it isn't shrinking to

`home/` was on its way to a residue — the part a plugin structurally could not
carry — once the plugin channel was verified end to end ([#48][issue-48]):

| Would have stayed deployed | Why |
| --- | --- |
| `CLAUDE.md`, `AGENTS.md` | Policy prose can't ride a plugin. Both are generated from `context/fragments/` — edit the fragment, run `python3 tests/compose-context.py --write` |
| `settings.json`, `settings.json.md` | Permission allowlists can't ride a plugin |
| `retired-paths` | Read by the pruner at `~/.claude/retired-paths` |
| `bin/claude-prune-retired` | Invoked by dotfiles after each apply |

That is not happening: #48 was closed and the channel withdrawn, so the whole
of `home/` stays on the chezmoi route and the deployed surface is not
shrinking. The table survives as a statement of what a plugin structurally
cannot carry, which is most of why it was never the right primary channel.

`/end-session` step 11 remains the backstop. It compares `chezmoi
managed` against the real contents of `~/.claude/commands/` and
`~/.claude/bin/`, so it catches drift the list doesn't know about — a
file retired without a list entry, or one left by another tool.

[dotfiles-371]: https://github.com/pmgledhill102/dotfiles/issues/371
[dotfiles-392]: https://github.com/pmgledhill102/dotfiles/issues/392
[issue-311]: https://github.com/pmgledhill102/agentic-coding-config/issues/311
[issue-312]: https://github.com/pmgledhill102/agentic-coding-config/issues/312

[issue-125]: https://github.com/pmgledhill102/agentic-coding-config/issues/125

## Skills, and the one surviving command

Everything here ships as an [Agent Skill](https://agentskills.io) under
`home/skills/`, one `<name>/SKILL.md` each with `name` + `description`
frontmatter. Claude Code registers a skill as the same `/name` a slash command
would give, so `/setup-python` works exactly as before. Skills are the portable
unit: native in Claude Code, the primary customisation unit in Codex, and read
by OpenCode, Gemini CLI, Cursor and Copilot too (ADR-0014).

`home/commands/gcp-credentials.md` is the one command left. It has no skill
counterpart on a workstation, and it carries Claude-specific tool references —
it reaches a sandbox by another route anyway, `cloud/bootstrap.sh` writing it
to `~/.agents/skills/`.

Each `/setup-*` skill contains:

1. Tool installation commands
2. Configuration file contents
3. Pre-commit hook registration
4. CI workflow snippet
5. Dependabot ecosystem configuration

**New project setup:**

```text
/setup-repo       # GitHub repo settings + branch protection (run first)
/setup-common     # Local tooling foundation (depends on branch protection for auto-merge)
/setup-python     # Language-specific tooling
```

### There used to be twins

Until [#313][issue-313] each of these shipped **twice** on a workstation: as
`home/commands/<name>.md` and as `home/skills/<name>/SKILL.md`, from the same
source, registering the same `/name`. Two identical bodies that could drift
apart, and a CI job whose whole purpose was to notice when they did.

They were to be retired at the plugin cutover ([#48][issue-48]); that cutover
was declined and the issue closed, so the duplication was judged on its own
merits instead. Both cloud profiles had already shipped `skills/` and no
`commands/` since ADR-0018, with `/start-session` resolving to the skill and
behaving identically — the precedent this followed.

Because chezmoi never deletes a target it has stopped managing, retiring them
meant 20 entries in `home/retired-paths`, not 20 deletions. See
["Deleting a file here does not delete it on machines"](#deleting-a-file-here-does-not-delete-it-on-machines).

Skill bodies carry no `$ARGUMENTS` / `$1` / `` !`cmd` `` / `@file` templating —
Codex's parser rejects those — so arguments arrive as free text ("the user names
the target language in their request"). `/start-session`, `/end-session` and
`/retrospective` are *composed* from `context/skills/` ([#265][issue-265]);
the rest are written directly.

[issue-48]: https://github.com/pmgledhill102/agentic-coding-config/issues/48
[issue-313]: https://github.com/pmgledhill102/agentic-coding-config/issues/313
[issue-265]: https://github.com/pmgledhill102/agentic-coding-config/issues/265

**Maintenance and review:**

```text
/repo-review      # Currency audit: ADR validity, deprecated deps, stale docs, dead code
```

`/repo-review` is portable — runs on any repo. Per-language scanners are
required only when their manifest is detected (e.g. `pip-audit` only if
`pyproject.toml` exists). Action items are emitted as **GitHub Issues**,
following the conventions in
[`docs/github-issues-workflow.md`](docs/github-issues-workflow.md); on a repo
with no GitHub remote they land as a markdown report at
`docs/reviews/repo-review-YYYY-MM-DD.md`.

**GCP credentials:**

```text
/gcp-credentials  # request human-approved, short-lived GCP access for a session
```

Drives `home/bin/gcp-credentials`, the client half of the credential broker
(ADR 021 in [`gcp-org-management`][gcp-org-management]). One Discord approval
creates a grant of 1–7 days; inside it the helper silently re-mints 1-hour
tokens **straight to disk**, so no credential ever reaches tool output, the
transcript, or the model's context. Needs a request key and broker URL
configured once per machine — see the command doc.

[gcp-org-management]: https://github.com/pmgledhill102/gcp-org-management

**Day-to-day coding:**
Claude Code edits files → hooks auto-run → Claude sees failures → fixes
them. No context spent on rules — tooling output *is* the context.

## Hook configuration examples

The hooks actually shipped in
[`home/settings.json`](home/settings.json) are the reference implementation,
and [`home/settings.json.md`](home/settings.json.md) carries the rationale for
each one. The two examples below are lifted from them, so the shapes here are
real.

There are two events, `PreToolUse` and `PostToolUse`, and each entry nests a
`hooks` array inside a matcher. The matcher matches **tool names** —
`Bash`, `Write`, `Edit` — not filesystem verbs.

**Gating a command before it runs (`PreToolUse`):**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/bin/precommit-claude-hook",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

There is **no `PreCommit` event**. Commit-stage linting is done by matching
`Bash` and having the hook script inspect the command it was handed, which is
what `precommit-claude-hook` does; blocking requires `exit 2`, the only
non-zero code that both stops the call and returns stderr to Claude.

**File-level auto-fix after a write (`PostToolUse`):**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "FILE_PATH=$(jq -r '.tool_input.file_path // empty'); [[ \"$FILE_PATH\" == *.tf ]] && terraform fmt \"$FILE_PATH\" || true",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

The edited path arrives as JSON on the hook's **stdin** and is parsed with
`jq`.

## MCP servers

[Model Context Protocol](https://modelcontextprotocol.io/) servers extend
Claude Code with external data sources and tools. They're configured
per-user via `claude mcp add` and stored in `~/.claude.json`.

The setup script that wires them up — `run_onchange_setup-claude.sh` —
lives in [dotfiles][dotfiles], not in this repo. It runs as part of
`chezmoi apply` and reads API keys from `~/.secrets` (also managed by
dotfiles, via chezmoi age encryption). On machines without the API keys
or without the `claude` CLI, the setup script degrades gracefully.

This boundary exists because MCP setup is a machine-bootstrap concern (it
calls `claude mcp add`, modifies `~/.claude.json`), not a content concern
— so it stays with the rest of the bootstrap machinery in dotfiles. This
repo holds the *content* that flows into `~/.claude/`.

## Customisation

- **Project overrides**: add `.claude/settings.json` in any repo to extend / override user-level hooks.
- **Subdirectory context**: add `CLAUDE.md` files in subdirectories for monorepo language-specific context.
- **New languages**: copy an existing setup command and adapt the tool list.

## Files that must stay in sync

`home/settings.json` (machine-readable) and `home/settings.json.md`
(annotated companion documenting the *why* for each rule) **must change
together**. JSON doesn't allow comments, so the `.md` file is how the
rationale travels with the rules. CI fails the PR if one changes without
the other.

## Editing flow

1. Edit content in this repo.
2. PR, watch CI, merge.
3. On any machine: `dotup` (which is `chezmoi update -v`) — pulls dotfiles, refreshes the external, applies. `~/.claude/` reflects the new content.
4. Restart Claude Code on that machine to pick up settings/hooks changes.

## Related

- [dotfiles](https://github.com/pmgledhill102/dotfiles) — the wiring repo (chezmoi externals declaration, MCP setup script, age-encrypted secrets).
- [Claude Code documentation](https://docs.claude.com/en/docs/claude-code/overview).
