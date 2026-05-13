# CLAUDE.md

## GitHub MCP

- **Prefer `mcp__github__*` tools over the `gh` CLI for all GitHub operations** when the GitHub MCP server is connected. Only fall back to `gh` if the MCP server is unavailable or a specific capability is missing
- Common mappings: PRs (`create_pull_request`, `pull_request_read`, `update_pull_request`, `merge_pull_request`, `list_pull_requests`, `search_pull_requests`), reviews (`pull_request_review_write`, `add_comment_to_pending_review`, `add_reply_to_pull_request_comment`), issues (`issue_read`, `issue_write`, `list_issues`, `search_issues`, `add_issue_comment`), releases (`get_latest_release`, `list_releases`, `get_release_by_tag`), repo content (`get_file_contents`, `list_commits`, `get_commit`, `list_branches`, `create_branch`), search (`search_code`, `search_repositories`)
- PR review workflow: create a pending review with `pull_request_review_write` (method: "create"), add line comments with `add_comment_to_pending_review`, then submit with `pull_request_review_write` (method: "submit_pending")

## Git Workflow

- Always create feature branches for changes -- never commit directly to main
- Create PRs with `mcp__github__create_pull_request` and merge via `mcp__github__merge_pull_request` (method: "squash", delete_branch: true)
- Watch the CI checks and ensure they pass
- Don't merge your own PRs - let them be reviewed by someone else
- Before pushing follow-up commits to a PR branch, always check the PR is still open via `mcp__github__pull_request_read` (method: "get"). The user often reviews and merges PRs via the GitHub UI while work continues — if already merged, create a new branch and PR instead
- When multiple related changes span different concerns, ask the user whether to use one branch or separate branches before committing

## Agent Config (`~/.claude/` files)

- **`~/.claude/` is chezmoi-managed from `pmgledhill102/agentic-coding-config`.** Do not edit these files directly — chezmoi will overwrite on the next apply and the change is lost. This includes `~/.claude/CLAUDE.md` itself, `~/.claude/settings.json`, slash commands under `~/.claude/commands/`, hooks, scripts under `~/.claude/bin/`, everything sourced from the `home/` directory of that repo.
- **To request a change, open a GitHub issue against `pmgledhill102/agentic-coding-config`** (auto-approved via `gh issue create --repo pmgledhill102/*` — keep `--repo` as the first flag for the allow rule to match). Describe what should change and why; add acceptance criteria if useful. The user sweeps the GH-issue inbox into beads via `/bd-import-github-issues` at the start of a-c-c sessions and addresses tickets there, where the chezmoi source actually lives.
- **Do not reach across repos to make the edit yourself.** Cross-repo file edits (e.g. `cd ~/dev/agentic-coding-config && edit home/...` from a session in another project) bypass the issue queue, skip the review/PR flow, and pollute the current session's context with unrelated work. Leave a message; don't reach across.

## Beads (bd)

- **Prefer `bd-push-safe` over bare `bd dolt push`**: the shim at `~/.claude/bin/bd-push-safe` strips the cache hooks that `bd init` / `bd bootstrap` re-create from `init.templatedir`. On machines where dotfiles git-templates invoke the pre-commit framework, bare `bd dolt push` fails with `fatal: this operation must be run in a work tree`; `bd-push-safe` is a drop-in replacement that just works. Tracked upstream as `agentic-coding-config-o5w`; once that lands the shim becomes a no-op and can be removed.

## Commit & PR Style

- Use multiple `-m` flags for multi-paragraph commit messages: `git commit -m "Title" -m "Body" -m "Co-Authored-By: ..."`
- Do NOT use heredocs (`cat <<'EOF'`) or ANSI-C quoting (`$'...\n...'`) in bash commands — heredocs create multi-line bash that doesn't match permission rules, and ANSI-C quoting gets flagged for hiding characters

## Process Guidelines

- **3 strikes rule**: After 3 failed attempts debugging the same issue, stop and question the entire approach before trying again
- **Check release notes before upgrading CLI tools**: Use `mcp__github__get_latest_release` / `mcp__github__list_releases` or check the changelog before upgrading. Breaking changes (e.g., dropped backends, renamed flags) waste significant time when discovered mid-migration
- **Test chezmoi template changes locally before pushing**: Use `HOME=/tmp/test chezmoi init --source <path> --dry-run` to verify behaviour in a clean environment before relying on CI
- **Lint before pushing**: Always run the relevant linter/test suite locally before `git push`. Only push if everything passes — avoids CI round-trips
- **Use native binaries over package runners**: When a linter/formatter is installed on PATH (`which <tool>`), invoke it directly (e.g. `markdownlint-cli2 "path"`) rather than wrapping it in `npx`/`pipx`/`uvx`. Wrappers introduce version drift from what CI and pre-commit use, are slower, and may trigger permission prompts
- **Single-concern PRs**: Each PR should contain a single logical change. If multiple tasks are completed in a session, create separate PRs for each rather than bundling unrelated changes
- **PR-stacking discipline**: only claim "stacked on" when the second branch literally has the first as parent (`git log --oneline first..second` shows just the second's commits). Branching both off `main` and writing "stacked on PR #N" in the body is misleading — reviewers can merge in any order, and the second PR's diff includes the first's changes. If they're truly independent, branch each from `main` and don't say stacked
- **Batch reads before edits**: When modifying multiple files, read all target files first, then make all edits — avoids "file not read yet" errors on parallel Edit calls
- **Always create a beads issue**: Even for quick single-file fixes, run `bd create` before starting work — maintains the audit trail and keeps the habit consistent

## Shell Scripts

- **Target POSIX sh or ensure macOS/zsh compatibility**: Avoid bash-only builtins (`mapfile`, `readarray`, `declare -A`). Be aware that `$(( expr ))` returns exit code 1 when result is 0 (breaks `set -e`), and empty arrays behave differently in zsh with `set -u`
- **Verify CLI flags before using them — for both commands you run AND advice you give the user**: Run `<tool> --help` or `<tool> help <subcommand>` locally before committing or before recommending a flag in chat. `--no-lock`-style hallucinations waste a round-trip whether they fire in your bash call or in the user's terminal after you suggest them
