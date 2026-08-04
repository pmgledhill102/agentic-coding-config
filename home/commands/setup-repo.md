Configure GitHub repository settings and branch protection for this project. This is independent of local tooling setup — run it before or after `/setup-common`.

> **Note:** This command uses `gh repo edit` and `gh api` to modify remote GitHub settings. Each call will prompt for approval.

## Modes

| Invocation | What runs |
| --- | --- |
| `/setup-repo` | The full baseline — steps 1–8 below |
| `/setup-repo --labels-only` | **Step 7 only** (work-tracking labels), then a short confirmation. Skips repo settings, merge strategy, secret scanning, branch protection and verification entirely |

`--labels-only` exists for **infra and secondary repos** that will never get the full treatment — a Terraform-only sibling repo, a fork used as a mirror — but that still need the `P0`–`P4` / `type: *` label set so cross-repo Issues filed against them can follow the convention in `agentic-coding-config` `docs/github-issues-workflow.md`. Without it such repos carry only GitHub's defaults and `gh issue create --label "type: task,P2"` fails.

Step 7's established-taxonomy guard applies **unchanged** in this mode: a repo with a purposeful labelling scheme of its own is still left alone.

## What to configure

### 1. Detect current state

Before making changes, gather the current repository configuration:

- Run `gh repo view --json name,owner,defaultBranchRef,deleteBranchOnMerge,mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed,isPrivate,hasWikiEnabled,hasProjectsEnabled` to get repo metadata
- Run `gh api repos/{owner}/{repo}/branches/{default_branch}/protection` to check existing branch protection (a 404 means none is configured)
- Check if `.github/workflows/` exists and list workflow files to detect CI

Display a summary table showing **current vs proposed** values before applying any changes.

### 2. Repository settings

Apply all settings in a single `gh repo edit` call:

```sh
gh repo edit \
  --delete-branch-on-merge \
  --enable-squash-merge \
  --enable-merge-commit=false \
  --enable-rebase-merge=false \
  --enable-auto-merge \
  --allow-update-branch \
  --enable-wiki=false \
  --enable-projects=false
```

If wiki or projects are currently enabled, note this in the summary but still disable them. Most hobby projects don't use these features.

### 3. Squash merge commit message format

Set the default squash merge commit message to use the PR title:

```sh
gh repo edit --enable-squash-merge --squash-merge-commit-message pr-title
```

`--enable-squash-merge` must be in the **same invocation** even though step 2 already enabled it: `gh` gates the message flag on the enable flag being present in the same call. Without it, `gh repo edit` prints its help text, exits 0, and applies nothing — the output looks like documentation, not an error, so check that it actually applied.

### 4. Secret scanning (public repos only)

If the repository is **public**, enable secret scanning and push protection:

```sh
gh repo edit --enable-secret-scanning --enable-secret-scanning-push-protection
```

If the repository is **private**, skip this step and note: "Secret scanning requires GitHub Advanced Security (paid) for private repos. Skipping."

### 5. Branch protection

Determine the CI status check names to require. Prefer deriving them from an **actual completed run** — `gh pr checks <n>` on a recent PR, or `gh api repos/{owner}/{repo}/commits/{sha}/check-runs --jq '.check_runs[].name'` — rather than reading the workflow YAML: the rendered check name can differ from the job key, and a wrong string here blocks every PR (see below). Fall back to reading `name:` values from `pull_request`-triggered jobs in `.github/workflows/` only when no run exists yet.

Two hazards to warn the user about while doing this:

- **Required checks are a rename trap.** Branch protection stores check names as opaque strings. Rename or remove a CI job and the old name is required forever, never reports, and every PR is blocked with no failing check to point at — nothing warns you. Whenever a CI job is renamed, removed, or a language port swaps one check for another, the protection contexts must be updated in the same change.
- **Path-filtered jobs cannot be required checks.** A job behind a `paths:` filter never reports on PRs it skips, so PRs touching other files block forever. `/setup-common` and the language skills deliberately suggest path filters — those jobs are ineligible; only require checks that run on every PR.

Apply branch protection to the default branch using the GitHub API. The JSON payload should contain:

- `required_status_checks.strict`: `true` (branch must be up-to-date before merging)
- `required_status_checks.contexts`: array of detected CI check names, or `[]` if no CI workflows exist
- `required_pull_request_reviews`: `null` (solo developer — cannot require approvals from others)
- `enforce_admins`: `true` (critical — prevents admin-level tokens and coding agents from bypassing rules)
- `restrictions`: `null` (not applicable for personal repos)
- `required_linear_history`: `true` (complements squash-only strategy)
- `allow_force_pushes`: `false`
- `allow_deletions`: `false`

Use `gh api -X PUT repos/{owner}/{repo}/branches/{default_branch}/protection` with the payload. Do not use heredocs to pass the JSON — use `--input` with process substitution or write a temporary file.

If the repo has no CI workflows, the `contexts` array will be empty. This still prevents direct pushes to the default branch and enforces PRs, but won't require any specific checks to pass. Note this and suggest running `/setup-common` to add CI.

If branch protection already exists, show the current configuration alongside the proposed one so the user can see what will change. The PUT endpoint **replaces** the entire protection config — existing custom settings (like specific required reviewers or additional status checks) will be overwritten.

### 6. Default branch name check

If the default branch is `master` instead of `main`, **do not rename it automatically**. Renaming is disruptive (breaks CI, open PRs, local clones). Instead, display a warning with the manual steps:

```text
Warning: Default branch is 'master'. Consider renaming to 'main':
  git branch -m master main
  git push -u origin main
  gh api -X PATCH repos/{owner}/{repo} -f default_branch=main
  git push origin --delete master
```

### 7. Work-tracking labels

*This is the step `--labels-only` runs on its own (see Modes above).*

**Guard: skip this step in repos with an established label taxonomy.** Run
`gh label list` first — if the repo already has a purposeful labelling scheme
(e.g. `lifeos`, whose `kind:`/`effort:`/`area:`/`list:` labels are a format
contract parsed by its mobile apps), do NOT add the standard set; the local
taxonomy is authoritative. Only bootstrap repos with default/no labels.

Create the standard work-tracking label set (see `agentic-coding-config`
`docs/github-issues-workflow.md`). `--force` makes this idempotent —
existing labels are updated, not duplicated:

```sh
gh label create "P0" --color b60205 --description "Critical" --force
gh label create "P1" --color d93f0b --description "High" --force
gh label create "P2" --color fbca04 --description "Medium" --force
gh label create "P3" --color 0e8a16 --description "Low" --force
gh label create "P4" --color c5def5 --description "Backlog" --force
gh label create "type: epic" --color 1d76db --force
gh label create "type: feature" --color 1d76db --force
gh label create "type: task" --color 1d76db --force
gh label create "type: bug" --color 1d76db --force
```

### 8. Verify

In `--labels-only` mode, verify with `gh label list` alone — confirm the nine labels exist — and stop. Do not touch repo settings or branch protection.

After a full run, verify the configuration took effect:

- Run `gh repo view --json deleteBranchOnMerge,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed` and confirm values match
- Run `gh api repos/{owner}/{repo}/branches/{default_branch}/protection` and confirm the protection rules are in place
- Display a final summary showing all applied settings

## Important

- This command modifies **remote GitHub settings**, not local files. It is safe to re-run (idempotent).
- Branch protection PUT replaces the entire config. If a repo has custom protection rules (e.g., required reviewers from a team), review the current config before overwriting.
- Some branch protection features require GitHub Pro on private repos. If the API returns a 403, explain this to the user.
- The `enforce_admins` setting is the most important for agent safety — without it, admin-level tokens bypass all other branch protection rules.
- Required status check names are stored as opaque strings — remind the user that renaming a CI job later silently orphans the requirement and blocks all PRs until the protection is updated.
