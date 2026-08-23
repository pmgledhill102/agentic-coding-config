### 2. Read context

Keep this lean — it feeds interpretation, not candidate generation:

- **Current repo**: `git rev-parse --show-toplevel` (if any). Not in a git repo → treat the retro as cross-repo by default; every action becomes an Issue against `pmgledhill102/paul-context`.
- **Current branch + state**: `git status` (branch name, dirty/clean).

Do **not** probe for which surface this is. This file is composed for one surface (ADR-0018 principle 1), so steps 5 and 6 already state the levers and the durable-lesson route that apply here — there is nothing left for a `command -v` to decide.
