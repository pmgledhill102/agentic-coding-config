# agentic-coding-config

Claude Code configuration: slash commands, hooks, settings, MCP. Mounted at
`~/.claude/` on every machine via [chezmoi externals][chezmoi-externals]
from my [dotfiles][dotfiles] repo.

[chezmoi-externals]: https://www.chezmoi.io/reference/special-files-and-directories/chezmoiexternal-format/
[dotfiles]: https://github.com/pmgledhill102/dotfiles

## How this gets onto your machine

This repo's content sits at `~/.claude/` on every machine. The wiring lives
in `dotfiles`:

```toml
# dotfiles' home/.chezmoiexternal.toml.tmpl
[".claude"]
type = "git-repo"
url = "https://github.com/pmgledhill102/agentic-coding-config.git"
refreshPeriod = "168h"
```

`chezmoi apply` (or `dotup`) clones this repo into chezmoi's source state
under `.claude/`, then applies it to `~/.claude/`. `refreshPeriod` controls
how often the external is re-fetched.

**One-line mental model:** files at the **root** of this repo map directly
to `~/.claude/`. So `commands/foo.md` → `~/.claude/commands/foo.md`,
`settings.json` → `~/.claude/settings.json`, etc. No chezmoi naming
conventions inside the repo (no `dot_` prefix, no `.tmpl` suffix on
most files) — chezmoi mounts the tree as-is.

History before 2026-05-03 is preserved here from the original `dotfiles`
location at `home/dot_claude/` via `git filter-repo`. Older commit
messages still reference that path; that's expected.

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

## Layout (mapped to `~/.claude/`)

```text
.                          → ~/.claude/
├── settings.json          → ~/.claude/settings.json     # Universal hooks (every repo)
├── settings.json.md                                     # Annotated companion (must stay in sync)
├── CLAUDE.md.tmpl         → ~/.claude/CLAUDE.md         # Universal policy
├── commands/              → ~/.claude/commands/         # Slash command library
├── bin/                   → ~/.claude/bin/              # Helper executables (start/end-session-gather-state)
└── adrs/                                                # Architecture decision records (this repo only — not deployed)
```

`adrs/`, `.github/`, `.beads/`, `.markdownlint.yaml`, `.pre-commit-config.yaml`,
this `README.md` — these are repo-meta files, **not** deployed into
`~/.claude/`. They're filtered out by chezmoi's apply step (some implicitly
because they're at root and not deployable, the README explicitly via
dotfiles' `.chezmoiignore`).

## Slash commands

Each `/setup-*` command contains:

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

**Maintenance and review:**

```text
/repo-review      # Currency audit: ADR validity, deprecated deps, stale docs, dead code
```

`/repo-review` is portable — runs on any repo. Per-language scanners are
required only when their manifest is detected (e.g. `pip-audit` only if
`pyproject.toml` exists). Action items are emitted as Beads tasks when the
project uses Beads, otherwise as a markdown report at
`docs/reviews/repo-review-YYYY-MM-DD.md`.

**Day-to-day coding:**
Claude Code edits files → hooks auto-run → Claude sees failures → fixes
them. No context spent on rules — tooling output *is* the context.

## Hook configuration examples

**Pre-commit hook (Layer 2):**

```json
{
  "hooks": {
    "PreCommit": [
      { "command": "pre-commit run --all-files 2>&1 | tail -40" }
    ]
  }
}
```

**File-level auto-fix (Layer 3):**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "write_file|edit_file|create_file",
        "command": "prettier --write $CLAUDE_FILE_PATHS 2>&1 | tail -5"
      }
    ]
  }
}
```

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

`settings.json` (machine-readable) and `settings.json.md` (annotated
companion documenting the *why* for each rule) **must change together**.
JSON doesn't allow comments, so the `.md` file is how the rationale travels
with the rules. CI fails the PR if one changes without the other.

## Editing flow

1. Edit content in this repo.
2. PR, watch CI, merge.
3. On any machine: `dotup` (which is `chezmoi update -v`) — pulls dotfiles, refreshes the external, applies. `~/.claude/` reflects the new content.
4. Restart Claude Code on that machine to pick up settings/hooks changes.

## Related

- [dotfiles](https://github.com/pmgledhill102/dotfiles) — the wiring repo (chezmoi externals declaration, MCP setup script, age-encrypted secrets).
- [Claude Code documentation](https://docs.claude.com/en/docs/claude-code/overview).
