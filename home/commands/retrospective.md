Run a retrospective on this session and route findings into the right places: beads in the current repo, GitHub Issues for cross-repo work, and memory writes for durable lessons. Do **not** append to `~/.claude/retros.md` — that file is retired (see `paul-context/decisions/2026-05-03-beads-per-repo-issues-as-inbox.md`).

## Steps

### 1. Read context

- **Current repo**: `git rev-parse --show-toplevel` to identify which repo we're in (if any).
- **Current branch + state**: `git status` (branch name, dirty/clean).
- **Beads workspace**: `bd ready` and `bd list --status=in_progress` (so the retro knows what was already in flight).
- **Memory dir**: list `~/.claude/projects/<project>/memory/` (path matches the cwd-derived project key) and read `MEMORY.md` so you know what's already captured and don't propose duplicates.
- **Settings**: read `~/.claude/settings.json` for permission-related observations.

If we're not inside a git repo, treat the retro as cross-repo by default — every action becomes an Issue against `pmgledhill102/paul-context`.

### 2. Analyse the session

Review the full conversation history and evaluate each of these dimensions. Skip any that aren't relevant.

- **Approval friction**: Which tool calls required manual approval? Were any repeatedly approved and should be added to `allowedTools` in settings? Note the specific tool patterns.
- **CI round-trips**: How many push-then-fix cycles happened? What caused each failure? Could any have been caught locally first?
- **Errors and debugging**: What errors were encountered? How long did each take to resolve? Were any red herrings?
- **Approach pivots**: Where did the initial approach fail and require a different strategy? What was learned?
- **Prompt clarity**: Were instructions clear enough, or did ambiguity cause wasted work?
- **Tool gaps**: Were there tasks that no available tool handled well?
- **Missing tools**: Were any CLI tools, SDK components, or binaries expected but not installed or not at the required version? For each:
  - What was attempted and what error or fallback occurred?
  - Is the tool installable via Homebrew, apt, pip, npm, or a component manager (e.g., `gcloud components install alpha`)?
  - Should the tool be added to the dotfiles repo (e.g., Brewfile, chezmoi scripts) so it's provisioned across all workstations?
- **MCP opportunities**: Were CLI tools used via Bash where an MCP server could provide safer, more granular access? Look for:
  - **Approval friction from dual-use CLIs**: Commands used read-only (e.g., `gh api` to query releases) but couldn't be auto-approved because the same command can also perform destructive actions. An MCP server with scoped, read-only tools would eliminate this friction.
  - **Repeated Bash commands for API queries**: Chains of `gh`, `gcloud`, `aws`, `kubectl`, or similar CLI calls that could be replaced by a dedicated MCP server offering structured, auto-approvable tools.
  - **Already-connected MCP servers that went unused**: Check if configured MCP servers had tools that could have replaced Bash commands used in this session.
  - For each opportunity, name the specific MCP server (if one exists) or note that one should be found/built.
- **Claude addon opportunities**: Did this session manually perform work that an official Claude skill, plugin, or Anthropic-published MCP server already handles? Distinct from the MCP bullet above (that one targets read-only CLI friction); this one targets procedural automation that's already packaged. Prefer official/Anthropic-published addons over community equivalents and over hand-rolled slash commands.
  - **Skills**: A repeated procedure that overlaps with an installed or marketplace skill. Check `~/.claude/skills/` and the in-session "available skills" list before proposing a new slash command.
  - **Plugins**: A coherent bundle (skill + commands + hooks) a published Claude Code plugin would provide in one install. Check `claude plugin marketplace` before bundling something in-house.
  - **Anthropic-published MCP servers**: Was a third-party/community MCP (or a raw CLI in Bash) used where Anthropic now ships a first-party equivalent?
- **Memory candidates**: What durable lessons should travel across sessions? Look for:
  - Validated patterns confirmed in this session ("X approach worked, keep doing it").
  - Anti-patterns to avoid ("Don't Y because Z").
  - User preferences expressed or implied ("the user prefers terse summaries").
  - Non-obvious facts about the user's repos, systems, or workflow.
- **Beads hygiene**: Were issues created before work started? Were they closed properly?
- **Slash command opportunities**: Did this session perform a procedure that's likely to be repeated — either across other projects, or periodically in this one? Strong signals:
  - The user explicitly mentioned having other projects/contexts that need the same treatment.
  - The procedure had non-obvious ordering, workarounds, or gotchas that would be easy to forget on a re-run.
  - Five-plus coherent sequential steps completed a single logical task.
  - A back-out/retry happened because a step was performed in the wrong order.
  - Investigation took disproportionate time relative to the eventual fix.

  For each candidate, propose: a command name (kebab-case), a one-line description, the key pre-flight checks, and the gotchas the prompt must surface. Existing commands live in `agentic-coding-config/home/commands/` (deployed to `~/.claude/commands/`) — check there first to avoid duplicates.

- **Slash command improvements**: Did this session invoke any existing slash command (or manually perform work that an existing one should have handled)? For each:
  - Was a step missing, wrong, or stale?
  - Did instructions cause a wrong decision via ambiguity?
  - Did we deviate from the command's plan? Why — and should the command codify the deviation?

  Recommend the specific edit (file path + which section).

### 3. Categorise findings

For each finding, decide what kind of artifact it should produce:

| Kind | When to use | How to produce |
| --- | --- | --- |
| **Same-repo bead** | Action whose subject is the current repo | `bd create --title=... --type=<task/bug/feature> --priority=N` (priority 0-4; P2 is "do this soon", P3 is "next time we touch this", P4 is "backlog") |
| **Cross-repo Issue** | Action whose subject is a *different* personal repo (the finding mentions e.g. dotfiles when retro is in agentic-coding-config) | `gh issue create --repo pmgledhill102/<target> --title=... --body=...` — picked up by `/start-session` there via `/bd-import-github-issues` |
| **paul-context Issue** | Cross-cutting or no-clear-home findings | `gh issue create --repo pmgledhill102/paul-context --title=... --body=...` |
| **Memory write** | Durable lesson that should auto-load on future sessions | `Write` to `~/.claude/projects/<project>/memory/<slug>.md` with frontmatter, then `Edit` `MEMORY.md` index |
| **Settings change** | Permission to add/move, hook to register, env var to set | Recommend invoking `/update-config` (the harness skill); or, if simple, propose the exact edit |
| **Observation only** | Something noted but not actionable ("everything went smoothly") | No artifact; mention in the summary, that's enough |

### 4. Routing heuristics for "which repo?"

When a finding clearly mentions a target, route there. Otherwise apply this default split:

- **Brewfile / package lists / shell config / OS bootstrap / chezmoi machinery** → `dotfiles`
- **Slash commands / hooks / `~/.claude/settings.json` / MCP server config / `home/CLAUDE.md`** → `agentic-coding-config`
- **Engineering principles / personal direction / repo registry / archive list / decisions** → `paul-context`
- **Genuinely unsorted / "I had a thought"** → `paul-context` (default fallback)

### 5. Propose

Show the user a single table of proposed artifacts. **Do not create anything yet.** Format:

```text
Proposed retrospective output:

#  Kind        Where                       Title / Memory key                                Priority
1  bead        <current repo>              Add git-filter-repo to Brewfile                  P4 task
2  issue       pmgledhill102/dotfiles      Document the bd-dolt-push pre-commit conflict    —
3  memory      feedback                    bd-dolt-push hook bypass workaround              —
4  settings    /update-config              Allow `Bash(rg --json *)` (read-only)            —
5  observation —                           Session was clean overall, no friction worth     —
                                           encoding

Reply 'yes' to create all, override per-item ('1: priority=2, type=bug'),
'skip <n>' to drop, or 'cancel' to abort.
```

Wait for explicit confirmation. Don't proceed on ambiguous input.

### 6. Execute

For each confirmed artifact:

- **bead** (same-repo): `bd create --title="..." --description="..." --type=... --priority=...` — capture the new ID for the summary.
- **issue** (cross-repo): `gh issue create --repo pmgledhill102/<repo> --title="..." --body="..."` — capture the URL.
- **memory**: Write the memory file with proper frontmatter (`name`, `description`, `type` of `user|feedback|project|reference`), then Edit `MEMORY.md` to add a one-line index entry. Follow the conventions in the parent CLAUDE.md auto-memory section.
- **settings**: invoke `/update-config` for non-trivial changes; for a single `allowedTools` addition, propose the exact diff and apply if confirmed.

If any single create fails, surface the error and continue with the rest. Don't roll back successful artifacts on partial failure.

### 7. Do NOT write to retros.md

The file is retired. If `~/.claude/retros.md` still exists locally from before, leave it alone — the user can `rm` it. Don't read from it, don't append to it, don't reference it in artifacts.

### 8. Brief summary

Print a compact wrap-up:

```text
Retrospective complete.

  Beads created (here):       3 — paul-context-abc, paul-context-def, paul-context-ghi
  Issues raised cross-repo:   2 — github.com/.../issues/14, github.com/.../issues/15
  Memories saved:             1 — feedback_xyz.md
  Settings changes:           1 (use /update-config to apply)

Next /start-session in the cross-repo'd repos will sweep the new Issues into beads.
```

## Guidelines

- Be specific and actionable — not "improve error handling" but "add `google_project_service` explicit depends_on to prevent 403 race conditions".
- Use exact tool patterns for permission recommendations, e.g., `Bash(chezmoi apply)`.
- For missing tools, include **both** the immediate install command (e.g., `brew install foo`) **and** the dotfiles change needed to provision it everywhere (e.g., "add `foo` to `home/Brewfile.tmpl`"). Recommend the user install the tool now AND raise the dotfiles bead so it persists across machines.
- For MCP recommendations, explain the **specific friction being solved** (e.g., "spent 5 approval prompts on read-only `gh api` calls"). Include the MCP server name/repo if known, and note whether it should be project-level or user-level config.
- For Claude addon recommendations, **name the specific skill/plugin/MCP and mark it official vs community**, and cite the manual work or hand-rolled slash command it would replace. Default to suggesting an existing official addon before proposing a new in-house slash command.
- For new slash command proposals, include the **proposed name**, a **one-sentence description**, and the **most important gotcha or pre-flight check** the command must encode.
- For slash command improvement recommendations, reference the **command file path** and cite the **specific deviation or failure mode** observed this session.
- Memory writes should follow the auto-memory conventions in the global CLAUDE.md: lead with the rule/fact, then `**Why:**` and `**How to apply:**` lines for `feedback` and `project` types.
- For descriptions on beads/Issues, cross-reference the relevant decision record or principle in `paul-context` if the action is implementing a decided direction (e.g. "implements paul-context-oed" or "see paul-context/decisions/2026-05-03-...md").
- If the session was uneventful with no notable friction, say so briefly in step 5's table as a single observation row, and stop. Don't manufacture artifacts.
- Reference specific errors, file paths, and bead IDs in artifact descriptions where relevant.

## What changed from the previous version

This command used to append a markdown entry to `~/.claude/retros.md`. That flow is retired because:

- **Sandbox-agent reachability**: remote Claude Code sandboxes can't see local files like `~/.claude/retros.md`. Beads + GitHub Issues are network-reachable.
- **Single-master-file decay**: a chronological journal that nothing else reads becomes a write-only log. Beads/Issues integrate with the rest of the work-tracking flow.
- **Cross-repo work needs the right home**: an action surfaced during a `dotfiles` retro that affects `agentic-coding-config` should land in *that* repo's tracker, not in a single shared file.

See `paul-context/decisions/2026-05-03-beads-per-repo-issues-as-inbox.md` for the design rationale, and `paul-context/decisions/2026-05-03-personal-infra-public-private-split.md` for the wider three-repo architecture this fits into.
