## Pre-flight

This command **requires a git-backed repository** — but it does not check for one itself. The gather script does, and it looks one level down before giving up: a container handed several repos as siblings starts the session in their parent, where a bare `git rev-parse` fails while the repo being worked in sits directly beneath.

So make **no standalone Bash call before the gather**. Run the gather (Phase 1) and branch on what it reports:

- **`repo_resolution`** — cwd was not a repo, exactly one repo sat beneath it, and the gather ran there. `cd` to its `repo=` value before any later step (the script's own `cd` died with it), and name the repo in the summary. No prompt: one candidate is not a choice.
- **`repo_candidates`** — several repos sat beneath cwd. It is the only section and the script exits 2, but it does not come back empty-handed: each `candidate=` line carries that repo's own `dirty=`, `unpushed=` and `stashes=` counts, probed read-only and without network ([#450](https://github.com/pmgledhill102/agentic-coding-config/issues/450)). Report **every** candidate with its counts before asking anything — a repo nobody chose is otherwise a repo nobody looked at, and on a sandbox a non-zero `unpushed=` is work one reclaimed container away from gone whichever repo it sits in. Then ask which repo to tidy, `cd` there, and re-run the gather. Never guess.
  The tidy-up runs in the chosen repo only. The others were **checked, not cleaned** — carry that distinction into the step 15 summary, which has a scope line for it, rather than letting one repo's "none" stand for the container.
- **`not_a_git_repo`** — no repo in cwd and none beneath it. Print the line it contains and stop. Do not run any further checks, do not proceed to Phase 2.
