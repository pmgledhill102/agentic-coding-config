## Surface

This file is the cloud-sandbox composition of the skill (ADR-0018). The
workstation composition is a separate file, so nothing below has to ask which
surface it is running on, and nothing below describes a machine this is not.

**Where the helper scripts are.** `cloud/bootstrap.sh` installed them under
`~/.claude/bin/`, which is where every surface now keeps them:

```sh
~/.claude/bin/<script>
```

**How GitHub is reached: the MCP server, not `gh`.** The gather script's
GitHub issue sections do not work on this surface and are not expected to.
`gh` is either absent or, on an Anthropic-hosted sandbox, present but unable to
list issues: `gh issue list` goes through GraphQL, which the egress proxy
blocks for every Claude Code session. Repo-scoped REST paths are a separate
lane, and the proxy has both 403ed them
([#273](https://github.com/pmgledhill102/agentic-coding-config/issues/273),
[#276](https://github.com/pmgledhill102/agentic-coding-config/issues/276)) and
allowed them, so the script's REST probe may pass. Either way the issue
sections never return usable data — a `gh-unavailable` / `gh-unauthorized`
sentinel, or a raw GraphQL 403 — and the GitHub MCP server is the only route.

That is a settled property of the container, not a failure to detect. Step 1
therefore issues the MCP queries as ordinary work of its own, rather than
waiting to see a sentinel and recovering from it. Tool names below are Claude
Code's spelling (`mcp__github__list_issues`); a client that namespaces MCP
tools differently is naming the same server and the same tool.

**No chezmoi here.** `cloud/bootstrap.sh` wrote most of `~/.claude/` at build
time and the platform launcher writes there too, so there is no source tree to
be behind and nothing to apply — and presence says nothing about a file's age
or owner. What is worth checking is how old the bootstrap is — step 5b.

**The container is disposable.** Anything not committed and pushed is lost when
it is reclaimed, which is what makes the brief's unpushed-commits line matter
more here than on a machine that will still be there tomorrow.
