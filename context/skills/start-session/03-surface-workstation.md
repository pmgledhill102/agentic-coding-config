## Surface

This file is the workstation composition of the skill (ADR-0018). The sandbox
composition is a separate file, so nothing below has to ask which surface it is
running on.

**Where the helper scripts are.** Prefer the plugin-relative path and fall back
to the chezmoi one:

```sh
${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/<script>
```

Both spellings are auto-approved in `settings.json`. Under chezmoi the variable
is unset and this resolves to `~/.claude/bin/`; under a plugin install it
resolves inside the plugin. Do not hard-code either.

**How GitHub is reached: `gh`, inside the gather.** `gh` is on PATH here and
authorised for repo data, so the gather script answers the GitHub questions
itself and the steps below just read its output. That is why the gather is a
shell script and not a series of tool calls — an MCP tool is not callable from
a subprocess, so one script call replaces several round trips.

Any GitHub operation this skill performs **outside** the gather still prefers a
structured GitHub API tool over the CLI where the client offers one.
