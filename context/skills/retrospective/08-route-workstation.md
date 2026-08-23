### 6. Categorise and route

For each proposal and observation, decide what artifact it produces:

| Kind | When to use | How to produce |
| --- | --- | --- |
| **Journal entry** | Always (unless the session was uneventful — then skip and stop). Carries the narrative, the closed-loop fate summary, and every observation that didn't make the proposal cap | Draft via the inbox/promote pattern — see step 8 |
| **Same-repo Issue** | Proposal whose subject is the **current cwd's repo** | Create an issue in the current repo with a `type: <task/bug/feature>` label and a `P0`–`P4` priority (P2 is "do this soon", P3 is "next time we touch this", P4 is "backlog") — `mcp__github__issue_write` when connected, else `gh issue create --title=... --label "type: <type>,P<n>"`. **Body MUST include**: "From retro: paul-context/journal/<file>.md" |
| **Cross-repo Issue** | Proposal whose subject is a *different* personal repo from cwd | Create an issue against `pmgledhill102/<target>` — `mcp__github__issue_write` with an explicit `owner`/`repo`, else `gh issue create --repo pmgledhill102/<target>`. Picked up by `start-session` there. **Body MUST include** the journal cross-reference |
| **paul-context Issue** | Cross-cutting or no-clear-home findings | Create an issue against `pmgledhill102/paul-context`, same two routes as above. **Body MUST include** the journal cross-reference |
| **Durable lesson** | A lesson that should reach future sessions | **Surface-dependent — see below** |
| **Settings change** | Permission to add or remove, hook to register, env var to set | File an Issue against `pmgledhill102/agentic-coding-config` describing the change and why — same routing as any other a-c-c finding. **Never edit a `settings.json` directly** (see 6b) |
| **Observation only** | Noted but below the proposal bar | No artifact; mention in the journal's Observations section |

**The durable-lesson route on this machine is a memory file.** It is the memory row of step 5's lever table, and it works here because the machine persists:

`Write` to `~/.claude/projects/<project>/memory/<slug>.md` with frontmatter (`name`, `description`, `type` of `user|feedback|project|reference`), then `Edit` `MEMORY.md` to add a one-line index entry, following the auto-memory conventions in the global CLAUDE.md.

A memory file is **machine-local**, which is the thing to weigh when choosing this route over an Issue. It reaches future sessions on this machine and no others. A lesson that should change behaviour everywhere — on every machine, and in every container — belongs in an Issue against the repo whose lever applies, usually `agentic-coding-config`, as well as or instead of a memory file.

#### 6a. No cd-shortcut

**Always name the target repo explicitly. Never `cd` into it.** Even when the target repo is checked out at a known path locally, do NOT change into it to file the issue from there. Retros run from a remote sandbox don't have target repos cloned — the command must be portable.

Both routes satisfy this, because both take the repo as an argument rather than inferring it from the working directory: `mcp__github__issue_write` with an explicit `owner`/`repo`, or `gh issue create --repo pmgledhill102/<target>`. Either works identically from a sandbox or a laptop.

Prefer MCP when it is connected, and fall back to `gh` where it is not and `gh` is present. Which of the two exists is a property of the surface: **`gh` is absent from Claude cloud sandboxes**, where MCP is the only route, so the `gh` forms here are for workstations and headless runs that have it. They are written out because the *operation* is what matters, not the tool.

#### 6b. Never edit settings.json — file an a-c-c Issue

Permissions, hooks, env vars and everything else in `~/.claude/settings.json` are **managed centrally** by `pmgledhill102/agentic-coding-config` and delivered per surface — by chezmoi on a workstation, by `cloud/bootstrap.sh` in a sandbox. A retro's job is to *route* a settings finding, not to apply it:

- **Do not edit `~/.claude/settings.json`.** It is generated on both surfaces: chezmoi overwrites it on the next apply, and the bootstrap rewrites it on the next run. Either way the change is silently lost.
- **Do not "helpfully" redirect the change into the current project's `.claude/settings.json` or `.claude/settings.local.json` instead.** A globally-useful permission parked in one project repo only works in that repo, is invisible to the a-c-c inbox, and diverges from the managed set. This substitution is the specific failure this section exists to prevent.
- **Do not invoke `/update-config`** for managed settings — that skill edits settings files in place, which is exactly the wrong outcome here. (It remains the right tool when the user is deliberately configuring a project-local harness setting, unrelated to a retro finding.)
- **Do** file an Issue against `pmgledhill102/agentic-coding-config` with the exact rule (e.g. `Bash(rg --json *)`), the friction observed this session, and whether it's read-only. Same body requirements as any other cross-repo Issue, including the journal cross-reference.

**The one exception**: a setting that is genuinely specific to the *current* repo and belongs to it permanently — a project-scoped hook, or a permission for a tool only this repo uses. That still goes in the repo's **checked-in** `.claude/settings.json` via the normal branch/PR flow, never as an untracked local edit. If the rule would be useful in any other repo, it isn't this case — file the a-c-c Issue.

#### 6c. Routing heuristics for "which repo?"

When a finding clearly mentions a target, route there. Otherwise apply this default split:

- **Brewfile / package lists / shell config / OS bootstrap / chezmoi machinery** → `dotfiles`
- **Skills / hooks / `~/.claude/settings.json` / MCP server config / agent policy** → `agentic-coding-config`. Policy now lives in `context/fragments/` (`core.md` portable, `provider-*.md` per provider, `env-*.md` per environment) and is composed into `home/AGENTS.md`, `home/CLAUDE.md` and `profiles/`. **Those outputs are generated — name the fragment, never the composed file.**
- **Engineering principles / personal direction / repo registry / archive list / decisions** → `paul-context`
- **Genuinely unsorted / "I had a thought"** → `paul-context` (default fallback)
