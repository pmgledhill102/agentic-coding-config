## Guardrails

- **No local branch deletion at all on this surface.** Step 6 is skipped, so neither `-d` nor `-D` has a caller here. If some future step needs to delete a local branch, it uses `-d`; a `-D` in a sandbox is deleting something disposable to save disk that is about to be freed anyway.
- **Never `git push --force` or `git reset --hard`.** Those aren't session-tidy operations; if they're needed, the user should drive them.
- **Never push a remote ref deletion.** The proxy refuses it and the failure looks like a network blip (§Surface, #252). Report it in the summary instead of retrying.
- **Never auto-merge PRs, auto-close issues, or auto-drop stashes.** Per-item judgment lives with the user (Tier 3).
- **Ask before every Tier 2 destructive action** (branch deletes, force-pushing). One y/n per batch is fine — don't ask per-branch if a single list is presented. There is no way to skip the prompt: a repo that wants different behaviour states it in its own `CLAUDE.md`.
- **Don't modify settings, config, or unrelated files.** This command's scope is git, GitHub, and process state only.
- **Never end on unpushed work without saying so.** Everything else this skill tidies can be tidied again next session; the container cannot.
