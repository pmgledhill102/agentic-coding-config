### 10. Brief summary

Print a compact wrap-up as plain labelled lines — label, colon, single space, value:

```text
Retrospective complete.

Closed loop: 4 accepted / 3 rejected / 1 pending; MCP-opportunity category retired
Journal: paul-context/journal/2026-08-19-acc-foo.md (Issue #57; pending /promote-journal-inbox)
Proposals: 2 of 3 cap used — 1 removal, 1 addition
Issues created (here): 1 — #41
Issues raised cross-repo: 1 — github.com/.../issues/14
Durable lessons: 1 — journal + issue

Next /start-session in the cross-repo'd repos will surface the new Issues as ready work.
```

**No label gutter, deliberately — do not pad the values back into a column.** The previous form aligned every value at column 31, which pushed the longest line to 143 characters, so the block wrapped and interleaved at terminal width. That is the same failure the step 7 table fixed, at 136 characters — this one was worse. Six wrap-up lines have no columns to compare down, so alignment buys nothing and costs the width that breaks it; leave the labels ragged and keep every line short enough to survive a narrow terminal.
