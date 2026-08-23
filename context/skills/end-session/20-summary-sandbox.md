### 14. Phase 1 summary

Print a concise summary. Each line says "none" loudly when clean, so noise scales with actual mess. (Step 1.5's fast-path also lands here directly when the predicate holds — same format, all "none" lines.)

- Branches pruned: `n/a (sandbox — container discarded)`
- Stashed/committed work this run: `<describe or "none">`
- **Unpushed commits: `<count, or "none">`** — the line that matters most here. The container is reclaimed after a period of inactivity and takes unpushed work with it, so anything non-zero is the one piece of mess that cannot be tidied in a later session.
- Main rebased: `<yes/no, behind/ahead counts>`
- CI on PRs touched this run: `<per-PR: green / running / FAILED: <workflow name + run URL>, or "no PR touched">`
- Open PRs needing action: `<count by category, "none", or "n/a (no GitHub route)">`
- Stashes outstanding: `<count, or "none">` — note that a stash in a disposable container is lost, not waiting
- Open issues assigned to you: `<count, "none", or "n/a (no GitHub route)">`
- Stale `~/.claude/` files: `n/a (sandbox)`
- Other worktrees: `n/a (sandbox — container discarded)`
- Background processes (reaped): `<count>`
- Background processes (user-owned, surfaced): `<count>`
- Could not prune (remote ref deletion refused): `<list or omit>`
- Anything skipped/surfaced: `<list>`
