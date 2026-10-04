### 5c. Parallel work — recently-pushed unmerged branches (Tier 1 — surface)

From gather section `unmerged_branches`. Another session's work exists as a
pushed branch long before it becomes a PR, and that gap is where parallel
sessions duplicate each other, file issues against premises already disproved,
and land contradictory edits to the same file. Neither the open-PR view nor
the issue list can see it; the branch can.

- **`count=0`**: silent.
- **`count >= 1`**: list each branch under `Parallel work:` in the brief, with
  its age and the paths it touches.

**Flag intersections — a bare list gets skimmed.** Compare each branch's paths
against this session's likely working set: the paths named in the prompt, and
the files the issue being picked up names. Every overlap becomes its own
"Needs attention" line naming both sides:

```text
  • claude/<branch> (pushed 3 hours ago, unmerged) touches
    health/training/data-flow.md, which this session is about to edit
```

When the working set is not known yet — the session starts with no task —
list the branches, and make the comparison once the task is chosen, before the
first edit. An overlap is a reason to read that branch's diff before writing,
not a block: the other session may have finished the work, or disproved the
premise, already.

Recency is what keeps this short. "Pushed in the last 48 hours and not merged"
is the handful of branches live right now, where an unbounded unmerged list is
the branch backlog, and a backlog at session start is noise that gets skimmed.
