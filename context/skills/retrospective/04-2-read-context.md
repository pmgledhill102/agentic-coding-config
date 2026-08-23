### 2. Read context

Keep this lean — it feeds interpretation, not candidate generation:

- **Current repo**: `git rev-parse --show-toplevel` (if any). Not in a git repo → treat the retro as cross-repo by default; every action becomes an Issue against `pmgledhill102/paul-context`.
- **Current branch + state**: `git status` (branch name, dirty/clean).
- **Surface**: `command -v chezmoi`. Present = workstation; absent = cloud sandbox. Used to pick the lever column in step 5 and the durable-lesson route in step 6 — nothing else branches on it.
