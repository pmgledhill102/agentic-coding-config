## Surface

This file is the cloud-sandbox composition of the skill (ADR-0018). The
workstation composition is a separate file, so nothing below has to ask which
surface it is running on, and nothing below describes a machine this is not.

**Where the helper scripts are.** `cloud/bootstrap.sh` installed them under
`~/.claude/bin/`, which is where every surface now keeps them:
`~/.claude/bin/<script>`.

**How GitHub is reached: the MCP server, not `gh`.** The gather script's GitHub
sections do not work on this surface and are not expected to. `gh` is either
absent or, on an Anthropic-hosted sandbox, present but 403ed by the egress
proxy on every repo-scoped API path
([#273](https://github.com/pmgledhill102/agentic-coding-config/issues/273),
[#276](https://github.com/pmgledhill102/agentic-coding-config/issues/276)). So
those sections return `gh-unavailable` or `gh-unauthorized` **every time**, and
the MCP server is the only route. Step 1 therefore issues the MCP queries as a
matter of course rather than waiting to see a sentinel and recovering from it.
Tool names below are Claude Code's spelling (`mcp__github__list_issues`); a
client that namespaces MCP tools differently is naming the same server and the
same tool.

**Walking away from a container is not walking away from a machine.** The
container is reclaimed after a period of inactivity, and everything not pushed
goes with it. That raises the stakes on steps 4 and 7 — unpushed work is the
only kind of mess here that cannot be tidied later — and lowers them to nothing
on steps that tidy local state for next time: branches, worktrees and stashes
in a disposable container are not debt, because there is no next time in it.

**Two things the sandbox refuses outright**, so that neither reads as a
failure to try harder:

- **Remote ref deletion.** The git proxy refuses it. `git push origin --delete
  <branch>` dies with a generic `unexpected disconnect` that looks like a
  network blip, and the MCP server has no delete-branch tool
  ([#252](https://github.com/pmgledhill102/agentic-coding-config/issues/252)).
  Branch cleanup at merge time (`delete_branch: true` on the merge call) is the
  route that works.
- **chezmoi.** There is none here, so step 11 has nothing to check.
