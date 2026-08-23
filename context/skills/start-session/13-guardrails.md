## Guardrails

- **Pre-flight gate is non-negotiable.** Never proceed when not in a git repo.
- **Never auto-rebase a feature branch** onto an advanced default branch. Surface the gap and stop. The user picks the strategy.
- **Never switch branches except when the upstream is gone and the tree is clean.** That single case (PR merged + branch auto-deleted on remote, no local uncommitted work) is auto-handled per Step 3. Otherwise, `start-session` reports state on whatever branch the user is on.
- **Don't push anything.** Pushes belong to `end-session` (for git/`main`). `start-session` is read-mostly. (Note: if the user says yes to the journal-promote prompt, `/promote-journal-inbox` runs its own commit + push against `paul-context` — that's the promote command's contract, not a carve-out here.)
- **Don't modify settings, config, or unrelated files.** Scope is git and GitHub-issue surface only.
