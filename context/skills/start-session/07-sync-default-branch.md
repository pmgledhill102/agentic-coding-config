### 3. Sync the default branch (Tier 1 / Tier 3)

Read `local_state`, including the `upstream_status` line (`alive` / `gone` / `none`). Behavior depends on which branch you're on:

- **On the default branch** (`branch` matches `default_branch`) and behind `origin/<default>`: run `git pull --rebase --autostash`. Tier 1.
- **On the default branch** and clean / up-to-date: silent.
- **On a feature branch with `upstream_status=gone` and a clean working tree**: auto-switch back to the default branch and bring it up to date. Tier 1.

  `upstream_status=gone` means an upstream is configured in `.git/config` but its remote ref has been pruned during fetch — the canonical signal that the PR was merged and the branch was auto-deleted on the remote. Run:

  ```sh
  git checkout <default_branch>
  git pull --rebase --autostash
  ```

  Add `auto-switched <feature> → <default> (upstream gone)` as an extra line under `Sync:` in the session brief. Leave the local feature branch in place — never delete it. The user can return to it with `git checkout <feature>` if they need to.

- **On a feature branch with `upstream_status=gone` but the working tree is dirty**: do NOT auto-switch. The dirty work might sit on top of commits that are now squash-merged into `main`, and switching would risk surprising the user. Surface as Tier 3: `<branch>'s upstream is gone (PR merged?) but tree is dirty — commit or stash, then switch manually`.
- **On a feature branch with `upstream_status=alive`** and `default_branch` advanced (`vs origin/<default>` shows non-zero `behind`): surface the count — "`<default>` is N commits ahead of your branch". Do **not** auto-rebase. Tier 3 — the user decides whether to rebase, merge, or carry on.
- **On a feature branch with unpushed commits** (non-zero `ahead` vs `@{u}`): surface the count. Don't push from here; that's `end-session`'s job.

Don't switch branches outside of the auto-switch case above.
