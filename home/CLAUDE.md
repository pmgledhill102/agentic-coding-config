# CLAUDE.md

## GitHub MCP

- **Prefer `mcp__github__*` tools over the `gh` CLI for all GitHub operations** when the GitHub MCP server is connected. Only fall back to `gh` if the MCP server is unavailable or a specific capability is missing
- Common mappings: PRs (`create_pull_request`, `pull_request_read`, `update_pull_request`, `merge_pull_request`, `list_pull_requests`, `search_pull_requests`), reviews (`pull_request_review_write`, `add_comment_to_pending_review`, `add_reply_to_pull_request_comment`), issues (`issue_read`, `issue_write`, `list_issues`, `search_issues`, `add_issue_comment`), releases (`get_latest_release`, `list_releases`, `get_release_by_tag`), repo content (`get_file_contents`, `list_commits`, `get_commit`, `list_branches`, `create_branch`), search (`search_code`, `search_repositories`)
- PR review workflow: create a pending review with `pull_request_review_write` (method: "create"), add line comments with `add_comment_to_pending_review`, then submit with `pull_request_review_write` (method: "submit_pending")

## Decision records (ADR tiers)

Decisions are recorded at three tiers, per
[ADR-0015](https://github.com/pmgledhill102/agentic-coding-config/blob/main/adrs/0015-tiered-adrs.md).
Every ADR declares which with a `Scope:` header line, so its blast radius is
stated rather than inferred from where it sits.

| Tier | Home | Holds |
| --- | --- | --- |
| **Personal** | `paul-context/decisions/` | Life/estate decisions, private rationale (private repo) |
| **User** | [`agentic-coding-config/adrs/`](https://github.com/pmgledhill102/agentic-coding-config/tree/main/adrs) | How I work with agents and repos, across the estate |
| **Repo** | `<repo>/adrs/` | Architecture and technology choices for that repo |

- **User-tier ADRs bind every repo.** They are public, so a sandbox session
  with no local clone can read them at the URL above. Consult them on demand;
  never copy them into a repo, because a copy drifts
- **Placement follows scope, not convenience.** The authoring test: *would
  this decision still bind if the current repo were archived?* If yes, it is
  not repo-tier
- **A repo may deviate from a higher tier, but only explicitly.** The repo
  ADR must name the ADR it deviates from and why. Silent divergence is the
  failure this rule exists to prevent
- Numbering is per-directory; cross-tier references use full URLs, which also
  work from sandboxes

## Git Workflow

- Always create feature branches for changes -- never commit directly to main
- Create PRs with `mcp__github__create_pull_request` and merge via `mcp__github__merge_pull_request` (`delete_branch: true`)
- **Merge method: `merge` by default, `squash` only to clean up a messy branch, never `rebase`.** Squash replaces a branch's commits with a new SHA, so anything built on that branch still carries the originals and re-applies work `main` already has — conflicts resolved against a change that already landed. Rebase-merge has the same defect for the same reason. A merge commit puts the branch's actual commits in `main`, so a dependent branch rebases to a no-op. Agentic PRs arrive as one or two already-written commits, so squash's benefit — collapsing WIP noise — is usually nothing, while its cost is paid every time. Reach for `squash` when the branch genuinely has fixup/WIP commits or several that aren't individually meaningful. The known trade-off: `git bisect` can descend into a commit that never passed CI on its own — use `git bisect --first-parent`, and `git log --first-parent` for the PR-level view
- Watch the CI checks and ensure they pass
- Don't merge your own PRs - let them be reviewed by someone else
- Before pushing follow-up commits to a PR branch, always check the PR is still open via `mcp__github__pull_request_read` (method: "get"). The user often reviews and merges PRs via the GitHub UI while work continues — if already merged, create a new branch and PR instead
- When multiple related changes span different concerns, ask the user whether to use one branch or separate branches before committing

## Agent Config (`~/.claude/` files)

- **`~/.claude/` is chezmoi-managed from `pmgledhill102/agentic-coding-config`.** Do not edit these files directly — chezmoi will overwrite on the next apply and the change is lost. This includes `~/.claude/CLAUDE.md` itself, `~/.claude/settings.json`, slash commands under `~/.claude/commands/`, hooks, scripts under `~/.claude/bin/`, everything sourced from the `home/` directory of that repo.
- **To request a change, open a GitHub issue against `pmgledhill102/agentic-coding-config`** (auto-approved via `gh issue create --repo pmgledhill102/*` — keep `--repo` as the first flag for the allow rule to match). Describe what should change and why; add acceptance criteria if useful. The user works the GH-issue inbox directly in a-c-c sessions, where the chezmoi source actually lives.
- The same applies in reverse — see Cross-Repo Work below. An `agentic-coding-config` session doesn't get to edit `dotfiles` either.

## Cross-Repo Work

- **Never edit files in a repo other than the one this session is working in.** Any direction, any repo pair: a project session editing `agentic-coding-config`, an `agentic-coding-config` session editing `dotfiles`, a `dotfiles` session editing `paul-context`. Cross-repo edits bypass the issue queue, skip that repo's review/PR flow, and pollute the current session's context with unrelated work. This holds even when the other repo is already cloned and writable, and even when the change is one line
- **File a detailed issue in the target repo instead.** This is encouraged, not a consolation prize — it's the sanctioned route. "Detailed" means implementable without rediscovering anything: exact file paths, the full snippet to add, the rationale, every gotcha already ruled out, and acceptance criteria. Write it so the fix is a mechanical edit for whoever picks it up
- **Reading another repo is fine, and verifying beats assuming.** Cloning a repo read-only to check the real state of a file before writing the issue is good practice — a-c-c's README carried a copy of dotfiles' `.chezmoiexternal.toml.tmpl`, and the issue quoted the live file instead
- **Say what you filed.** Report the issue number back in the session summary so the cross-repo thread isn't lost

## Work Tracking

- **All repos use GitHub Issues**, per the conventions in `agentic-coding-config` `docs/github-issues-workflow.md`:
  - Create an issue before starting work; close it via `Closes #<n>` in the PR body
  - Hierarchy via sub-issues (`gh issue create --parent <n>`); dependencies via `--blocked-by`
  - Priority labels `P0`–`P4`; type labels `type: epic|feature|task|bug` (issue types are org-only — labels ARE the convention on personal repos)
  - Some repos (e.g. `lifeos`) declare their own label taxonomy in their repo CLAUDE.md — that wins over the defaults above
  - **Use `gh issue list` or direct reads (`gh issue view <n>`) for anything time-sensitive — never `gh search issues`**: the search API is eventually consistent, so a just-created issue can be invisible to it for seconds to minutes. Deduplicate against `gh issue list --state all`, not search

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
- **Always create a tracking issue**: Even for quick single-file fixes, create a GitHub Issue in the repo before starting work — maintains the audit trail and keeps the habit consistent
- **WebFetch 403? Fall back to curl + pandoc**: Some sites (UESP, other MediaWiki / Cloudflare-fronted wikis) reject WebFetch's User-Agent before serving content. On HTTP 403, don't burn time on alternative URLs — go straight to:

  ```sh
  curl -sS -L -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15" "$URL" -o /tmp/page.html
  pandoc -f html -t gfm --wrap=none /tmp/page.html -o /tmp/page.md
  ```

  Then `Read` the markdown (or `grep` it for structured extraction). If the same site will be hit repeatedly, save the fetcher as a per-project script

## Shell Scripts

- **Target POSIX sh or ensure macOS/zsh compatibility**: Avoid bash-only builtins (`mapfile`, `readarray`, `declare -A`). Be aware that `$(( expr ))` returns exit code 1 when result is 0 (breaks `set -e`), and empty arrays behave differently in zsh with `set -u`
- **Verify CLI flags before using them — for both commands you run AND advice you give the user**: Run `<tool> --help` or `<tool> help <subcommand>` locally before committing or before recommending a flag in chat. `--no-lock`-style hallucinations waste a round-trip whether they fire in your bash call or in the user's terminal after you suggest them
- **Multi-step probe loops go in a script file, not inline**: For anything that loops over hosts/endpoints/cases, `Write` a script to the scratchpad and run `bash script.sh` rather than composing the loop in the Bash call. The interactive shell is **zsh**, which differs from bash in two ways that fail silently:
  - **No word-splitting on unquoted variables.** `set -- $TWO_WORDS` splits into two arguments in bash and stays one argument in zsh, so the loop runs once with a joined value and downstream parsing fails somewhere unrelated. zsh needs `${=VAR}` or a real array
  - **`:` is a modifier.** `"$MODEL:generateContent"` flirts with zsh's `:g`-style parameter-modifier parsing; write `${MODEL}:generateContent`. Bare `$VAR:` in a URL is a trap
- **Raw strings when patching file content via `python3` heredocs**: a regular triple-quoted payload turns `\n` in the *target* file's source (e.g. a Go or JSON string literal) into a real newline, producing a syntax error that surfaces a couple of tool calls later. Use `r'''…'''`, or better, use the `Edit` tool for surgical source changes
- **Prefer a tool's `--*-file` flag over inline content**: `gh issue create --body-file=PATH`, `gh pr create --body-file=PATH`, `--input` for `gh api` JSON. Cleaner than `--body "$(cat …)"`, avoids quoting edge cases, and renders correctly — this is the positive form of the heredoc ban above
