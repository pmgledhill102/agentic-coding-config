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
GitHub sections do not work on this surface and are not expected to. `gh` is
either absent or, on an Anthropic-hosted sandbox, present but 403ed by the
egress proxy on every repo-scoped API path — it authenticates identity
endpoints only ([#273](https://github.com/pmgledhill102/agentic-coding-config/issues/273),
[#276](https://github.com/pmgledhill102/agentic-coding-config/issues/276)). So
those sections return `gh-unavailable` or `gh-unauthorized` **every time**, and
the GitHub MCP server is the only route.

That is a settled property of the container, not a failure to detect. Step 1
therefore issues the MCP queries as ordinary work of its own, rather than
waiting to see a sentinel and recovering from it. Tool names below are Claude
Code's spelling (`mcp__github__list_issues`); a client that namespaces MCP
tools differently is naming the same server and the same tool.

**No chezmoi here.** `~/.claude/` was written by `cloud/bootstrap.sh` when the
container was built, so there is no source tree to be behind and nothing to
apply. What is worth checking instead is how old the bootstrap itself is —
step 5b.

**The container is disposable.** Anything not committed and pushed is lost when
it is reclaimed, which is what makes the brief's unpushed-commits line matter
more here than on a machine that will still be there tomorrow.
