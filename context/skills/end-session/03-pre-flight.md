## Pre-flight

This command **requires a git-backed repository** — but it does not check for one itself. The gather script does, and it looks one level down before giving up: a container handed several repos as siblings starts the session in their parent, where a bare `git rev-parse` fails while the repo being worked in sits directly beneath.

So make **no standalone Bash call before the gather**. Run the gather (Phase 1) and branch on what it reports:

- **`repo_resolution`** — cwd was not a repo, exactly one repo sat beneath it, and the gather ran there. `cd` to its `repo=` value before any later step (the script's own `cd` died with it), and name the repo in the summary. No prompt: one candidate is not a choice.
- **`repo_candidates`** — several repos sat beneath cwd. It is the only section and the script exits 2. List the candidates, ask which, `cd` there, and re-run the gather. Never guess.
- **`not_a_git_repo`** — no repo in cwd and none beneath it. Print the line it contains and stop. Do not run any further checks, do not proceed to Phase 2.
