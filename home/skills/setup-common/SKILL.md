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

### 8. Dependabot

The normative standard is [`docs/github-standards.md`](https://github.com/pmgledhill102/agentic-coding-config/blob/main/docs/github-standards.md) — read it rather than treating the samples below as the source of truth. `gcp-org-management` is the reference implementation; its two files carry inline rationale worth reading before copying.

**Dependabot has two halves and each is invisible from the other.** Repo *settings* (dependency graph, alerts, security updates) raise the alarm when an advisory lands; repo *files* decide how routine bumps arrive. Weekly bump PRs prove only the file half — a repo shipped them for months, on schedule, correctly labelled, while alerts were off. Steps 8a and 8b are not optional halves of each other.

#### 8a. Settings (every repo — two API calls, never wrong)

```sh
gh api -X PUT "repos/{owner}/{repo}/vulnerability-alerts"
gh api -X PUT "repos/{owner}/{repo}/automated-security-fixes"
```

Dependency graph must be on (private repos need it enabled explicitly; nothing below works without it), plus grouped security updates. Those sit under `security_and_analysis` on `PATCH /repos/{owner}/{repo}`, a surface that has changed shape more than once — **don't assume a scripted write took**: `GET` the repo back and read `security_and_analysis`. For a handful of repos the UI (Settings → Advanced Security) is the reliable path.

#### 8b. `.github/dependabot.yml` (every repo)

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directories:
      - "/"
    schedule:
      interval: weekly
      day: monday
    open-pull-requests-limit: 5
    cooldown:
      default-days: 7
    groups:
      actions:
        patterns: ["*"]
        update-types: [minor, patch]
      actions-major:
        patterns: ["*"]
        update-types: [major]
    commit-message:
      prefix: "ci"
```

If the file already exists, read it first and add only the missing ecosystem entry. Four things about this shape are load-bearing:

- **`cooldown` is not a lint nit.** This skill also installs auto-merge, so without it a freshly published malicious or broken version lands on the default branch with nobody looking. `dependabot-missing-cooldown` is a blocking semgrep rule. **But cooldown is not universally effective** — the docker ecosystem provides no publication date, so docker PRs carry *"Cooldown could not be applied"* and merge with no delay. For docker, required status checks are the only gate.
- **Per-severity cooldown keys (`semver-patch-days` and friends) are accepted by some ecosystems only** — `gomod` takes them, `github-actions` and `terraform` reject them. A rejected key **invalidates the entire file**, silently stopping every update stream in the repo, not just that setting. Add one to a new ecosystem only after checking it is accepted.
- **Group across directories, not per directory.** Use `directories:` (plural) with a list; the same dependency bumped in N directories otherwise arrives as N near-identical PRs that put each other behind under a strict up-to-date rule, each needing its own CI cycle.
- **Only name labels that already exist.** Dependabot does not create labels it is told to use, and naming an absent one risks it applying **none**. Check first, or omit the key.

#### 8c. Auto-merge (only repos whose CI proves something)

A repo without a check worth requiring does not get auto-merge — see the never-combination at the end of this section.

```yaml
name: Dependabot Auto-merge
on: pull_request

# Read-only is sufficient: fetch-metadata only reads, and both writes go
# through the PAT. Raising these grants nothing, and GitHub would still
# refuse an Actions-token approval.
permissions:
  contents: read
  pull-requests: read

jobs:
  automerge:
    if: github.event.pull_request.user.login == 'dependabot[bot]' && github.repository == '<owner>/<repo>'
    runs-on: ubuntu-latest
    steps:
      - name: Fetch update metadata
        id: metadata
        uses: dependabot/fetch-metadata@<full-sha> # <version>
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}

      # For a grouped PR, update-type is the LARGEST jump in the group, so a
      # group containing one major is treated as a major and skipped.
      - name: Approve and enable auto-merge (patch/minor)
        if: steps.metadata.outputs.update-type == 'version-update:semver-patch' || steps.metadata.outputs.update-type == 'version-update:semver-minor'
        env:
          GH_TOKEN: ${{ secrets.AUTOMERGE_PAT }}
          PR_URL: ${{ github.event.pull_request.html_url }}
        run: |
          if [ -z "$GH_TOKEN" ]; then
            echo "::error::AUTOMERGE_PAT is not set in the Dependabot secret store. Refusing to fall back to GITHUB_TOKEN: Actions may not approve pull requests, and a GITHUB_TOKEN merge does not trigger workflows that run on push to the default branch."
            exit 1
          fi
          if ! gh pr review --approve "$PR_URL"; then
            echo "::error::Approval failed with a non-empty AUTOMERGE_PAT. The most likely cause is that this repository is not on the token's selected-repositories list -- a fine-grained PAT's scope cannot be read from outside the token, so this is where a missed repo surfaces. Add ${{ github.repository }} to the AUTOMERGE_PAT repository list."
            exit 1
          fi
          gh pr merge --auto --merge "$PR_URL"

      - name: Leave majors for a human
        if: steps.metadata.outputs.update-type == 'version-update:semver-major'
        run: echo "Major update -- deliberately not auto-merged."
```

**`--merge`, not `--squash`.** Merge-commit is the estate default; squash drops commit trailers, which silently leaves `Closes #N` issues open. The cost is two commits per bump, accepted.

**Neither call may use `GITHUB_TOKEN`, for two independent reasons.** GitHub refuses an Actions-token approval outright (*"GitHub Actions is not permitted to approve pull requests"*); and a merge performed with it **does not trigger other workflows**, so on any repo where the push to the default branch runs a deploy, auto-merged changes would land and never apply. The job fails loudly rather than falling back.

#### 8d. The `AUTOMERGE_PAT` — do this when installing 8c

**One shared fine-grained token serves the whole estate**; installing the workflow means adding this repo to its list, not minting a new token. Both steps, in order:

1. **Add this repository to the `AUTOMERGE_PAT` token's selected-repositories list.** Skipping this is the failure the workflow's second guard exists to catch — the secret is present and non-empty, so the missing-PAT check passes and the approval fails with a bare 403. **A PAT's scope cannot be audited from outside**, so this step at install time is the only real control.
2. Store the token as a **Dependabot** secret (Settings → Secrets and variables → **Dependabot**), not an Actions secret. Dependabot-triggered runs read from the Dependabot store; a secret in the Actions store is simply empty at run time, with no error.

```sh
gh secret set AUTOMERGE_PAT --app dependabot --repo "<owner>/<repo>" --body "$TOKEN"
```

Permissions are Contents read/write plus Pull requests read/write, and no more. Contents write is the floor, not an over-grant: the merge writes to the base branch, and GitHub has no narrower "may merge but not push" permission.

Also enable **Allow auto-merge** in Settings → General (`/setup-repo` does this).

> **The combination that must never exist: auto-merge enabled with no required status checks on the default branch.** Without required checks `gh pr merge --auto` merges *immediately* — the "wait for CI" everyone assumes comes from the ruleset, not the flag. If a repo has no check worth requiring, it does not get 8c.

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
settings (branch ruleset, merge methods, secret scanning, labels).
```

The two commands are a pair that is easy to half-apply: this one writes local files, `setup-repo` configures the remote (different preconditions, different blast radius — the split is deliberate). Naming what `setup-repo` adds is the load-bearing part of the reminder; skip it only if `setup-repo` was already run this session.

## Important

- Do NOT blindly overwrite existing config files. Read them first and merge.
