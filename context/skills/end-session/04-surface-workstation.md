## Surface

This file is the workstation composition of the skill (ADR-0018). The sandbox
composition is a separate file, so nothing below has to ask which surface it is
running on.

**Where the helper scripts are.** chezmoi puts them at `~/.claude/bin/`, and
that is the spelling to use: `~/.claude/bin/<script>`. Earlier versions used
`${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/<script>` so one line could serve a
plugin install too; that channel was withdrawn (#312), the variable is never
set on this surface, and the fallback was the only branch that ever ran.

**How GitHub is reached: `gh`, inside the gather.** `gh` is on PATH here and
authorised for repo data, so the gather script answers the GitHub questions
itself and the steps below just read its output. That is why the gather is a
shell script and not a series of tool calls — an MCP tool is not callable from
a subprocess.

Any GitHub operation this skill performs **outside** the gather — checking a
PR's checks, closing an issue — still prefers a structured GitHub API tool over
the CLI where the client offers one.

**`~/.claude/` is chezmoi-managed here**, which is what makes step 11's stale-
file check meaningful: chezmoi never deletes a target whose source was removed,
so retired files accumulate until something looks for them.
