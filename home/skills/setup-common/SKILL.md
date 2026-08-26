---
name: setup-common
description: Set up the baseline development tooling for a project — pre-commit framework, gitleaks secret scanning, spell checking, Dependabot and the shared CI workflow. Run this first; the language-specific setup skills build on it.
---

# Set up common project tooling

## What to install and configure

### 1. EditorConfig

Create `.editorconfig` in the project root (if it doesn't already exist). If one exists, review it and suggest additions for any missing settings.

```ini
root = true

[*]
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
charset = utf-8
indent_style = space
indent_size = 2

[*.{go,py}]
indent_size = 4

[Makefile]
indent_style = tab
```

### 2. pre-commit framework

Create `.pre-commit-config.yaml` in the project root (if it doesn't already exist). If one exists, review it and suggest adding any missing hooks from below.

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: <latest tag>
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
      - id: check-merge-conflict

  - repo: https://github.com/gitleaks/gitleaks
    rev: <latest tag>
    hooks:
      - id: gitleaks
```

Look up the latest release tag for each repo and use those for the `rev:` values.

Do **not** run `pre-commit install` — nothing should write to `.git/hooks`. The config file is the source of truth, and it is enforced from two directions: a global pre-tool hook runs pre-commit on every `git commit`/`git push` the agent makes, and CI runs `pre-commit run --all-files` on every push. Manual terminal commits are CI-backed. Mention this model in the closing summary so the user knows why no git hook was installed.

If `pre-commit` is not installed, tell the user to install it (`brew install pre-commit`) and stop.

When adding hooks for a tool that is already a project or system dependency (prettier, eslint, golangci-lint, …), prefer a `repo: local` hook invoking the project's own binary over a `pre-commit/mirrors-*` repo — the mirrors pin their own copy of the tool, so the hook and the project can silently run different versions (and several mirrors are archived).

### 3. cspell (spell checking)

Create `cspell.json` in the project root (if it doesn't already exist). If one exists, review and suggest additions.

```json
{
  "version": "0.2",
  "language": "en-GB",
  "files": "\\.(md|txt|rst|yaml|yml)$",
  "ignorePaths": [
    "node_modules",
    "go.sum",
    "*.lock",
    ".git"
  ],
  "words": [
    "actionlint",
    "aquasecurity",
    "bandit",
    "brakeman",
    "bridgecrewio",
    "checkov",
    "chezmoi",
    "chezmoiexternal",
    "cleanups",
    "clippy",
    "coreutils",
    "cspell",
    "dependabot",
    "dotnet",
    "editorconfig",
    "errcheck",
    "eslint",
    "footgun",
    "frontmatter",
    "gitleaks",
    "godoc",
    "gofmt",
    "gofumpt",
    "goimports",
    "golangci",
    "gomod",
    "gosec",
    "gotchas",
    "govet",
    "govulncheck",
    "hadolint",
    "handoff",
    "hashicorp",
    "ineffassign",
    "jsdoc",
    "linters",
    "lockfiles",
    "markdownlint",
    "mkdocs",
    "mypy",
    "nuget",
    "phpdoc",
    "phpstan",
    "pipx",
    "pkill",
    "pytest",
    "pyupgrade",
    "rhysd",
    "rubocop",
    "ruff",
    "rustdoc",
    "rustfmt",
    "rustsec",
    "semgrep",
    "shellcheck",
    "shfmt",
    "shivammathur",
    "siloed",
    "speedup",
    "staticcheck",
    "streetsidesoftware",
    "subdirs",
    "temurin",
    "tflint",
    "tradeoffs",
    "trivy",
    "tseslint",
    "typecheck",
    "worktree"
  ],
  "dictionaries": ["en_GB", "softwareTerms", "companies", "misc"]
}
```

The `files` pattern limits cspell to prose-heavy file types — markdown, plain text, reStructuredText, and YAML. This avoids noise from code identifiers.

The seeded `words` list is deliberate, not decoration: it covers the names of every tool these setup skills install and the config identifiers their own templates write (the YAML samples above are spell-checked too, since `.yml` matches the `files` pattern), plus recurring dev jargon the base dictionaries miss. Without the seed, the very first `pre-commit run --all-files` flags dozens of words the skill itself just wrote. Do **not** seed user- or project-specific proper nouns (personal handles, repo names) — leave those for the consumer to add as they surface — and never add a word that is actually a typo.

Add a cspell pre-commit hook to `.pre-commit-config.yaml`:

```yaml
  - repo: https://github.com/streetsidesoftware/cspell-cli
    rev: <latest tag>
    hooks:
      - id: cspell
        types_or: [markdown, plain-text, yaml]
```

Look up the latest release tag and use it for the `rev:` value.

The `words` array is the project-specific dictionary. As cspell flags legitimate words during the verify step, add them here.

### 4. actionlint (GitHub Actions linting)

Add an actionlint pre-commit hook to `.pre-commit-config.yaml`:

```yaml
  - repo: https://github.com/rhysd/actionlint
    rev: <latest tag>
    hooks:
      - id: actionlint
```

Look up the latest release tag and use it for the `rev:` value.

### 5. semgrep (static analysis)

Add a semgrep pre-commit hook to `.pre-commit-config.yaml`:

```yaml
  - repo: https://github.com/semgrep/semgrep
    rev: <latest tag>
    hooks:
      - id: semgrep
        args: ["--config", "auto", "--error"]
        pass_filenames: false
```

Look up the latest release tag and use it for the `rev:` value.

The `--config auto` flag uses Semgrep's curated rulesets appropriate for the languages detected in the repo. The other two lines matter:

- `--error` — semgrep exits 0 on findings by default, so without it the hook always passes and the gate is decorative.
- `pass_filenames: false` — pre-commit hands hooks explicit filenames, and giving semgrep explicit paths makes it bypass its own default excludes (notably `*_test.go`), reporting findings CI never sees. Scanning the repo instead keeps hook and CI seeing the same thing.

### 6. .gitignore

Create `.gitignore` if it doesn't exist, or append missing entries. Ensure it includes at least:

```gitignore
# OS
.DS_Store
Thumbs.db

# Editors
*.swp
*.swo
*~
.vscode/
.idea/

# Environment
.env
.env.local
.env.*.local
```

Read any existing `.gitignore` first and only add lines that are missing.

### 7. GitHub Actions workflows

Create or update CI workflows. Gitleaks, cspell, and semgrep run on all files (no path filter). Actionlint only needs to run when workflow files change.

Add to `.github/workflows/ci.yml` (or create if needed):

```yaml
  gitleaks:
    name: Gitleaks
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    steps:
      - uses: actions/checkout@<full-sha> # <version>
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@<full-sha> # <version>
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  cspell:
    name: Spell Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<full-sha> # <version>
      - uses: streetsidesoftware/cspell-action@<full-sha> # <version>
        with:
          files: '**/*.{md,txt,rst,yaml,yml}'

  semgrep:
    name: Semgrep
    runs-on: ubuntu-latest
    container:
      image: semgrep/semgrep
    steps:
      - uses: actions/checkout@<full-sha> # <version>
      - run: semgrep scan --config auto --error
```

(`--error` for the same reason as the hook: without it findings don't fail the job.)

The gitleaks job's `permissions:` block is required: the default `GITHUB_TOKEN` no longer grants `pull-requests: read`, and `gitleaks-action` needs it in PR context to fetch the PR's commit list — without it, the first PR run fails with `403 Resource not accessible by integration`. Job-level rather than workflow-level keeps it least-privilege; cspell and semgrep don't need it.

Create a separate `.github/workflows/actionlint.yml` with a path filter (or add to existing CI with the same filter). `rhysd/actionlint` publishes no GitHub Action to pin, so use the official download script rather than `rhysd/actionlint@main` (a mutable branch reference that fails the repo's own semgrep gate):

```yaml
name: Actionlint
on:
  push:
    paths: ['.github/workflows/**']
  pull_request:
    paths: ['.github/workflows/**']

jobs:
  actionlint:
    name: Actionlint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<full-sha> # <version>
      - name: Download actionlint
        run: bash <(curl https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
      - name: Run actionlint
        run: ./actionlint -color
```

Don't duplicate if any of these jobs already exist. Every `uses:` reference must be pinned to a full commit SHA with a version comment — look up the latest release of each action and substitute the real SHA for `<full-sha>`, e.g.:

```yaml
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
```

A floating tag (`@v4`) or branch (`@main`) is a mutable reference — it fails the semgrep gate installed above (`github-actions-mutable-action-tag` is a blocking finding), so samples committed with floating tags fail their own repo's CI.

### 8. Dependabot auto-merge

Create `.github/workflows/dependabot-auto-merge.yml` (if it doesn't already exist):

```yaml
name: Dependabot Auto-merge
on: pull_request

permissions:
  contents: write
  pull-requests: write

jobs:
  auto-merge:
    runs-on: ubuntu-latest
    if: github.actor == 'dependabot[bot]'
    steps:
      - uses: actions/checkout@<full-sha> # <version>
      - run: gh pr review --approve "$PR_URL"
        env:
          PR_URL: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - run: gh pr merge --auto --squash --delete-branch "$PR_URL"
        env:
          PR_URL: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

`--squash` here is deliberate and is the one place it stays. The global default is merge-commit (see the Git Workflow section of the user's global agent policy), because squash's SHA rewrite punishes stacked branches — but a Dependabot PR is a single-commit version bump that nothing is ever stacked on, and one commit per bump keeps `main` readable. Don't "fix" this to match the default.

Also ensure `.github/dependabot.yml` exists with the base structure. If it doesn't exist, create it:

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    commit-message:
      prefix: "ci(deps)"
      include: "scope"
    labels:
      - "dependencies"
      - "github-actions"
    open-pull-requests-limit: 5
    cooldown:
      default-days: 7
```

If `.github/dependabot.yml` already exists, read it first and ensure the `github-actions` ecosystem entry is present. Don't duplicate entries.

The `cooldown` block is load-bearing, not a lint nit: this same skill installs auto-merge, so without a cooldown a freshly published malicious or broken version can land on `main` with nobody looking at it. Seven days gives upstream time to yank a bad release first. Every ecosystem entry — here and in the language skills — carries the same block (semgrep's `dependabot-missing-cooldown` rule blocks on entries without one).

> **Note:** Auto-merge requires branch protection or rulesets with required status checks enabled on the default branch. Without this, `--auto` merges immediately without waiting for CI.

### 9. Agent permissions for cloud sessions

A cloud session reads the project repo's `.claude/` and **nothing** from
`~/.claude/`, so anything it needs has to arrive by a route the repo or the
environment controls.

Do **not** stamp a marketplace or `enabledPlugins` declaration here. This
estate published its config as a Claude Code plugin for a while; that channel
was withdrawn, and a repo enabling it now would point at a marketplace that no
longer exists. Agent config reaches a sandbox through the environment's setup
script running `cloud/bootstrap.sh`, which is a property of the environment
rather than of any one repo — see `cloud/README.md`.

What *does* belong in the repo's `.claude/settings.json` is the **permission
allowlist**: it is the only place a cloud session reads permissions from, and
no delivery channel can carry it. Stamping a core allowlist is a reasonable
follow-on, deliberately not done automatically here — permissions are the one
thing worth deciding per repo rather than by template.

Whatever you put there, commit it; it is meant to be shared, not gitignored,
and if the repo already has `.claude/settings.json`, merge alongside whatever
is there rather than replacing it.

### 10. Verify

Run `pre-commit run --all-files` to confirm everything works. Fix any issues that come up.

### 11. Closing summary

End the closing summary with this reminder (verbatim or close to it):

```text
Local baseline applied. Run /setup-repo next to apply the GitHub-side
settings (branch protection, squash-merge rules, secret scanning, labels).
```

The two commands are a pair that is easy to half-apply: this one writes local files, `setup-repo` configures the remote (different preconditions, different blast radius — the split is deliberate). Naming what `setup-repo` adds is the load-bearing part of the reminder; skip it only if `setup-repo` was already run this session.

## Important

- Do NOT blindly overwrite existing config files. Read them first and merge.
