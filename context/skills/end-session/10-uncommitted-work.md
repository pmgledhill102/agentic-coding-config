### 4. Handle uncommitted or unpushed work (Tier 3)

Read from gather section `local_state`. Before any branch switching or deletion:

- **Dirty working tree** (non-empty `status` block): stop, show the user what's dirty, ask whether to (a) commit, (b) stash, or (c) abort the tidy-up. Do **not** silently stash.
- **Current branch has unpushed commits** and isn't `main` (non-empty `unpushed` block): surface this — ask whether to push (create PR if needed) or abort. Don't switch away from a branch with unpushed work without explicit permission.
