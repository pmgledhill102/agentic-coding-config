### 15. Phase 1 summary

Print a concise summary. Each line says "none" loudly when clean, so noise scales with actual mess. (Step 1.5's fast-path also lands here directly when the predicate holds — same format, all "none" lines.)

- Branches pruned (merged): `<list or "none">`
- Branches pruned (squash-merged): `<list or "none">`
- Stashed/committed work this run: `<describe or "none">`
- Main rebased: `<yes/no, behind/ahead counts>`
- CI on PRs touched this run: `<per-PR: green / running / FAILED: <workflow name + run URL>, or "no PR touched">`
- Open PRs needing action: `<count by category, "none", or "n/a (gh absent)">`
- Stashes outstanding: `<count, or "none">`
- Open issues assigned to you: `<count, "none", or "n/a (gh absent)">`
- Stale `~/.claude/` files: `<count, or "none">`
- Other worktrees: `<count, or "none">`
- Background processes (reaped): `<count>`
- Background processes (user-owned, surfaced): `<count>`
- GCP sandbox project created this session: `<project, "none", "n/a (no GCP grant this session)", or "n/a (broker client absent)", or "n/a (broker client predates this check)">` — surface only; it is the repo's, shared and durable, never deleted here
- Anything skipped/surfaced: `<list>`
