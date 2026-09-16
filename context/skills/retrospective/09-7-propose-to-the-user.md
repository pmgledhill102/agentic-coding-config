### 7. Propose to the user

Show the user a single table of proposed artifacts. **Do not create anything yet.** The journal entry is **always row 1** unless the session was uneventful (in which case the table has just one observation row and the flow stops). At most 3 rows are proposals; each names its lever and tier price.

Emit the closed-loop lines as prose, then the proposals as a **markdown table** — not as hand-aligned columns inside a fence:

```markdown
Closed loop: 4 accepted (2 paid off, 2 no evidence yet), 3 rejected, 1 pending.
Rejection record: MCP-opportunity findings 0/4 accepted — category retired this retro.

Proposed retrospective output:

| # | Kind | Where | Title / Slug | Lever / Tier | Pri |
| --- | --- | --- | --- | --- | --- |
| 1 | journal | paul-context | `2026-08-19-acc-retro-redesign` | — | — |
| 2 | issue | agentic-coding-config | Remove stale heredoc rationale (`core.md`) | Context / always-loaded (frees) | P2 task |
| 3 | issue | *current repo* | Cache lint deps in setup script | Installs / on-invoke | P3 task |
| 4 | observation | — | CI green first try; no friction | — | — |

Reply 'yes' to create all, override per-item ('3: priority=2, type=bug'),
'skip <n>' to drop, or 'cancel' to abort.
```

**A markdown table, deliberately — do not tidy it back into aligned columns.** The previous format hand-aligned the columns inside a `text` fence, which fixed the header row at exactly 136 characters, so every row wrapped and interleaved at terminal width — and it stayed that way from #263 until #437. Letting the renderer own the wrapping is the whole point: a narrow terminal degrades the table instead of destroying it, and issue references render as links rather than as inert text competing for column space.

The fence above is `markdown` so the literal pipe syntax is visible. It is the format to emit, not an illustration of one.

Wait for explicit confirmation. Don't proceed on ambiguous input.
