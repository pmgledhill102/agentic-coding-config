# Agent Instructions

This project uses **GitHub Issues** for issue tracking — see
[docs/github-issues-workflow.md](docs/github-issues-workflow.md) for the
conventions (sub-issue hierarchy, P0–P4 priority labels, `type: *` labels,
blocked-by dependencies).

## Quick Reference

```bash
gh issue list --search "is:open -is:blocked"   # Find available work
gh issue view <n>                              # View issue details
gh issue edit <n> --add-assignee @me           # Claim work
gh issue close <n> --comment "Shipped in #<pr>"  # Complete work
```

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**

```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**

- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

## Session Completion

**When ending a work session:**

1. **File issues for remaining work** — anything that needs follow-up
2. **Run quality gates** (if code changed) — tests, linters, builds
3. **Update issue status** — close finished work, comment on in-progress items
4. **Push to remote** — work is not complete until `git push` succeeds:

   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```

5. **Clean up** — clear stashes, prune remote branches
