### 7. Propose to the user

Show the user a single table of proposed artifacts. **Do not create anything yet.** The journal entry is **always row 1** unless the session was uneventful (in which case the table has just one observation row and the flow stops). At most 3 rows are proposals; each names its lever and tier price. Format:

```text
Closed loop: 4 accepted (2 paid off, 2 no evidence yet), 3 rejected, 1 pending.
Rejection record: MCP-opportunity findings 0/4 accepted — category retired this retro.

Proposed retrospective output:

#  Kind        Where                                Title / Slug                               Lever / Tier                     Priority
1  journal     paul-context/journal/                2026-08-19-acc-retro-redesign.md           —                                —
2  issue       pmgledhill102/agentic-coding-config  Remove stale heredoc rationale (core.md)   Context / always-loaded (frees)  P2 task
3  issue       <current repo>                       Cache lint deps in setup script            Installs / on-invoke             P3 task
4  observation —                                    CI green first try; no friction            —                                —

Reply 'yes' to create all, override per-item ('3: priority=2, type=bug'),
'skip <n>' to drop, or 'cancel' to abort.
```

Wait for explicit confirmation. Don't proceed on ambiguous input.
