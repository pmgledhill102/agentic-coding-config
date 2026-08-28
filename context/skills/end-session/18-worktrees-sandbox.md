### 12. Other worktrees (n/a here)

**Skipped on this surface**, for the same reason as step 6: a worktree is local
state on a disk that is about to be discarded. Surfacing it would ask the user
to think about tidying something the container is going to take with it anyway.

Report `n/a (sandbox — container discarded)` in the step 15 summary rather than
omitting the line, so "nothing to report" stays distinguishable from "not
checked".

The gather still emits its `worktrees` section — the script is one file shared
with the workstation composition — with one exception worth reading: **a
worktree holding uncommitted work is not a tidy-up item, it is unpushed work.**
That belongs to step 4, which does run here, and the summary's unpushed-commits
line is where it lands.
