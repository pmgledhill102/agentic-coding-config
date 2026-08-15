# CLAUDE.md — Claude Code adapter

Claude-specific guidance only. The portable policy is maintained once, in
AGENTS.md format, and imported here; machine-local guidance is imported from
`local-machine.md`.

@AGENTS.md

@local-machine.md

Anything portable belongs in `AGENTS.md`, not here. This file is for what
would be meaningless to Codex or OpenCode: Claude Code tool names, and the
MCP servers configured on this surface.

## GitHub MCP

- **Prefer `mcp__github__*` tools over the `gh` CLI for all GitHub operations** when the GitHub MCP server is connected. Only fall back to `gh` if the MCP server is unavailable or a specific capability is missing
- Common mappings: PRs (`create_pull_request`, `pull_request_read`, `update_pull_request`, `merge_pull_request`, `list_pull_requests`, `search_pull_requests`), reviews (`pull_request_review_write`, `add_comment_to_pending_review`, `add_reply_to_pull_request_comment`), issues (`issue_read`, `issue_write`, `list_issues`, `search_issues`, `add_issue_comment`), releases (`get_latest_release`, `list_releases`, `get_release_by_tag`), repo content (`get_file_contents`, `list_commits`, `get_commit`, `list_branches`, `create_branch`), search (`search_code`, `search_repositories`)
- PR review workflow: create a pending review with `pull_request_review_write` (method: "create"), add line comments with `add_comment_to_pending_review`, then submit with `pull_request_review_write` (method: "submit_pending")

### How the portable rules map to these tools

`AGENTS.md` states the policy; these are the calls that carry it out here.

| Policy (AGENTS.md) | Claude Code |
| --- | --- |
| Open a PR, delete the branch on merge | `create_pull_request`; `merge_pull_request` with `delete_branch: true` |
| Check the PR is still open before pushing follow-ups | `pull_request_read` (method: `get`) |
| Create an issue before starting work | `issue_write` |
| Sub-issue hierarchy and blocked-by dependencies | `sub_issue_write` |
| Never use issue *search* for anything time-sensitive | `list_issues` or `issue_read`, never `search_issues` |
| Check release notes before upgrading a CLI tool | `get_latest_release` / `list_releases` |

- `gh` equivalents remain correct when the MCP server is unavailable: `gh issue create --repo pmgledhill102/*` is auto-approved, and keeping `--repo` as the first flag is what makes the allow rule match

## Other MCP servers

Configured per-machine via `claude mcp add` and stored in `~/.claude.json`,
not in this repo. `home/settings.json.md` records which of their tools are
auto-approved and why.
