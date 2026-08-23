## Guardrails

- **`-D` (force delete) is allowed only for Batch B of step 6** — branches that are `[upstream: gone]` AND have an empty `git diff` against `main` (or a merged PR confirmed by the step 6 query). Everywhere else: always `-d`. If `-d` refuses, that's signal — surface it, don't override.
- **Never `git push --force` or `git reset --hard`.** Those aren't session-tidy operations; if they're needed, the user should drive them.
- **Never push a remote ref deletion.** The proxy refuses it and the failure looks like a network blip (§Surface, #252). Report it in the summary instead of retrying.
- **Never auto-merge PRs, auto-close issues, or auto-drop stashes.** Per-item judgment lives with the user (Tier 3).
- **Ask before every Tier 2 destructive action** (branch deletes, force-pushing). One y/n per batch is fine — don't ask per-branch if a single list is presented. There is no way to skip the prompt: a repo that wants different behaviour states it in its own `CLAUDE.md`.
- **Don't modify settings, config, or unrelated files.** This command's scope is git, GitHub, and process state only.
- **Never end on unpushed work without saying so.** Everything else this skill tidies can be tidied again next session; the container cannot.
