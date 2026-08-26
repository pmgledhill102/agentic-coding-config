# settings.json — Annotated Reference

This file documents `settings.json` with groupings and rationale.
**Keep this file in sync with `settings.json`** — when adding, removing, or
changing permission rules, update both files together.

## Permissions: allow

### BigQuery (read-only metadata)

`bq query` is **not** auto-approved — its `--use_legacy_sql=false` flag
doesn't constrain the query to SELECT, so it can execute DDL/DML.
Listing and schema-introspection are safe.

- `Bash(bq ls*)`
- `Bash(bq show*)`

### Brew (read-only + services)

- `Bash(brew --prefix *)`
- `Bash(brew info *)`
- `Bash(brew list *)`
- `Bash(brew search *)`
- `Bash(brew services *)`

### Chezmoi

- `Bash(chezmoi *)`

### Session-lifecycle scripts

The `/end-session` and `/start-session` slash commands delegate their
multi-line gather and pipeline steps to dotfiles-managed scripts in
`~/.claude/bin/`. Inline compound shell commands can't match
single-pattern allow rules (a command like `echo A; git status; echo B`
is one string to the matcher, not three matches), so extracting them to
scripts + one prefix rule per command removes recurring approval
prompts. Each rule covers current and future scripts of its respective
prefix; scoped narrowly so unrelated scripts in `~/.claude/bin/` still
prompt.

- `Bash(~/.claude/bin/end-session-*)`
- `Bash(~/.claude/bin/start-session-*)`
- `Bash(${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/end-session-*)`
- `Bash(${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/start-session-*)`

The matcher compares rule text against the command **before** shell expansion,
with `*` as the only wildcard. So a rule covering a command that contains a
shell variable has to contain that variable's characters *literally* — the
rule is never expanded, and neither is the command at match time.

That is why the second pair carries the full `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}`
spelling, defaults and all. The commands emit exactly one string, deliberately,
so a single line works on both delivery channels:

```sh
${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/start-session-gather-state
```

Good design for execution, and unforgiving for matching: it is neither
`~/.claude/bin/…` nor `${CLAUDE_PLUGIN_ROOT}/bin/…`, so a rule written as
either of those covers nothing. That was the state from #139 until #237 — four
rules, zero matches, every `/start-session` and `/end-session` prompting on its
first step with nothing to indicate why.

The `~/.claude/bin/` pair stays for anything that spells the tilde path
directly, including a human typing it, but is no longer what carries the
slash commands.

`tests/allowlist-covers-commands.py` now checks this mechanically — see the
note there on the one thing it cannot check.

See `docs/end-session-design.md` for the full rationale.

### GCP credential broker client

- `Bash(~/.claude/bin/gcp-credentials status)`
- `Bash(~/.claude/bin/gcp-credentials release)`

Exact commands, not a prefix — the deliberate omissions are the point.
`status` only reports local state and `release` only undoes local state, so
both are safe to run unattended. `request` is left prompting because it posts
an approval card to Discord and pings a human, and `revoke` because it ends a
grant the human granted; neither should happen without the user seeing it go
by. `refresh` is started by `request` and is not meant to be invoked directly.

See `home/commands/gcp-credentials.md` for the flow, and ADR 021 in
`pmgledhill102/gcp-org-management` for the design.

### draw.io (CLI export, read-only)

- `Bash(/Applications/draw.io.app/Contents/MacOS/draw.io *)`

### Containers (Podman)

- `Bash(hadolint *)`
- `Bash(podman build *)`
- `Bash(podman compose *)`
- `Bash(podman container prune *)`
- `Bash(podman info *)`
- `Bash(podman inspect *)`
- `Bash(podman logs *)`
- `Bash(podman machine *)`
- `Bash(podman network prune *)`
- `Bash(podman ps *)`
- `Bash(podman rm *)`
- `Bash(podman run *)`
- `Bash(podman push *)`
- `Bash(podman stop *)`

### GCloud (read-only operations, plus noted exceptions)

Enumerate specific subcommands rather than using wildcards in the middle
of commands. `gcloud storage` is restricted to `cat` and `ls` — no `cp`,
`rm`, or `mv`. Anything that isn't read-only carries its rationale under
its own heading — currently just `gcloud builds` (see below).

#### Artifacts

- `Bash(gcloud artifacts docker images list *)`
- `Bash(gcloud artifacts repositories describe *)`
- `Bash(gcloud artifacts repositories list *)`

#### Auth and config

`gcloud auth list` reports which accounts are configured; it prints no
credential material. The two `print-*-token` forms do, and are in the
Never Allow list below.

- `Bash(gcloud auth list *)`
- `Bash(gcloud config *)`
- `Bash(gcloud info *)`

#### Builds

**The one deliberate non-read-only rule in this section.** The wildcard
covers `gcloud builds submit`, which stages source, runs a build, and
pushes an image — it burns CPU time and money, but it is not
destructive: it creates new artifacts rather than mutating or deleting
existing ones, and a bad build fails without touching what is already
deployed. The read-only inspection calls (`log`, `describe`, `list`)
were the observed friction, but splitting them out while `submit` still
prompts leaves the prompts in place for the calls that actually recur
inside committed build scripts. Approving the whole subcommand is the
simpler rule.

- `Bash(gcloud builds *)`

#### Compute

- `Bash(gcloud compute backend-services describe *)`
- `Bash(gcloud compute backend-services list *)`
- `Bash(gcloud compute firewall-rules describe *)`
- `Bash(gcloud compute firewall-rules list *)`
- `Bash(gcloud compute forwarding-rules describe *)`
- `Bash(gcloud compute forwarding-rules list *)`
- `Bash(gcloud compute images list *)`
- `Bash(gcloud compute instances describe *)`
- `Bash(gcloud compute instances get-serial-port-output *)`
- `Bash(gcloud compute instances list *)`
- `Bash(gcloud compute instances reset *)`
- `Bash(gcloud compute network-endpoint-groups describe *)`
- `Bash(gcloud compute network-endpoint-groups list *)`
- `Bash(gcloud compute networks describe *)`
- `Bash(gcloud compute networks list *)`
- `Bash(gcloud compute networks subnets describe *)`
- `Bash(gcloud compute networks subnets list *)`
- `Bash(gcloud compute operations list *)`
- `Bash(gcloud compute shared-vpc *)`
- `Bash(gcloud compute target-http-proxies describe *)`
- `Bash(gcloud compute target-http-proxies list *)`
- `Bash(gcloud compute url-maps describe *)`
- `Bash(gcloud compute url-maps list *)`

#### Containers (GKE)

- `Bash(gcloud container clusters describe *)`
- `Bash(gcloud container clusters list *)`

#### DNS

- `Bash(gcloud dns managed-zones describe *)`
- `Bash(gcloud dns managed-zones list *)`
- `Bash(gcloud dns record-sets list *)`

#### Functions

- `Bash(gcloud functions describe *)`
- `Bash(gcloud functions list *)`

#### IAM

- `Bash(gcloud iam service-accounts describe *)`
- `Bash(gcloud iam service-accounts list *)`
- `Bash(gcloud iam workload-identity-pools describe *)`
- `Bash(gcloud iam workload-identity-pools providers describe *)`

#### Logging

`gcloud beta logging tail` streams log entries — read-only despite the
`beta` prefix. `gcloud secrets versions access` is **not** auto-approved
(reads secret material — credential-exfiltration risk).

- `Bash(gcloud beta logging tail *)`
- `Bash(gcloud logging read *)`

#### Projects and services

- `Bash(gcloud projects describe *)`
- `Bash(gcloud projects list *)`
- `Bash(gcloud services list *)`

#### Pub/Sub

- `Bash(gcloud pubsub subscriptions describe *)`
- `Bash(gcloud pubsub subscriptions list *)`
- `Bash(gcloud pubsub topics describe *)`
- `Bash(gcloud pubsub topics list *)`

#### Cloud Run

- `Bash(gcloud run jobs describe *)`
- `Bash(gcloud run jobs executions describe *)`
- `Bash(gcloud run jobs executions list *)`
- `Bash(gcloud run jobs list *)`
- `Bash(gcloud run revisions describe *)`
- `Bash(gcloud run revisions list *)`
- `Bash(gcloud run services describe *)`
- `Bash(gcloud run services list *)`

#### Scheduler

- `Bash(gcloud scheduler jobs describe *)`
- `Bash(gcloud scheduler jobs list *)`

#### Secrets Manager

- `Bash(gcloud secrets describe *)`
- `Bash(gcloud secrets list *)`
- `Bash(gcloud secrets versions describe *)`
- `Bash(gcloud secrets versions list *)`

#### Cloud SQL

- `Bash(gcloud sql instances describe *)`
- `Bash(gcloud sql instances list *)`

#### Storage (read-only)

`gcloud storage` is restricted to read-only subcommands — `cat`, `ls`,
`du`, and `buckets describe` / `buckets get-iam-policy`. No `cp`, `rm`,
or `mv`.

- `Bash(gcloud storage buckets describe*)`
- `Bash(gcloud storage buckets get-iam-policy*)`
- `Bash(gcloud storage cat *)`
- `Bash(gcloud storage du*)`
- `Bash(gcloud storage ls *)`

### gsutil (read-only, legacy CLI)

- `Bash(gsutil cat *)`
- `Bash(gsutil ls *)`
- `Bash(gsutil stat *)`

### GitHub CLI

Read/view operations, PR creation, and CI re-runs. PR merging is handled
manually (see Never Allow). Closing PRs/issues and `gh api` (which can
POST/DELETE) require prompting. These entries will be retired once the
GitHub MCP server is validated — see GitHub MCP section below.

- `Bash(gh issue create --repo pmgledhill102/*)` — narrower than `gh issue create *`. Restricts auto-approval to issues filed against the user's own repos. **Caveat**: Claude Code's Bash matcher is literal-prefix, so `--repo pmgledhill102/<name>` must be the **first flag** after `gh issue create` for the rule to match. Putting `--title` or `--body-file` first will fall back to manual approval. Symmetric `gh issue comment/edit/close --repo pmgledhill102/*` rules are deliberately deferred — they share the same shape and can be added when the friction surfaces.
- `Bash(gh issue list *)`
- `Bash(gh issue view *)`
- `Bash(gh pr checks *)`
- `Bash(gh pr create *)`
- `Bash(gh pr diff *)`
- `Bash(gh pr list *)`
- `Bash(gh pr view *)`
- `Bash(gh repo view *)`
- `Bash(gh run list *)`
- `Bash(gh run rerun *)`
- `Bash(gh run view *)`
- `Bash(gh run watch *)`
- `Bash(gh variable list *)`
- `Bash(gh workflow list *)`
- `Bash(gh workflow view *)`

### Git

Standard git workflow operations plus read-only porcelain/plumbing.
Destructive operations (`reset --hard`, `push --force`, `clean`,
`gc`, `prune`) still require prompting.

Deliberately **not** auto-allowed:

- `git config *` — the `--set` form mutates config; per CLAUDE.md,
  Claude must never update git config. Use an explicit prompt.
- `git symbolic-ref *` — has a set form (`git symbolic-ref <name>
  <ref>`). If needed, allow narrowly or prompt.
- `git reflog *` — `expire` / `delete` subcommands mutate the reflog.
- `git gc *`, `git prune *`, `git clean *`, `git fsck *`,
  `git archive *` — rewrite objects, remove data, or slow/specialised.

- `Bash(git add *)`
- `Bash(git blame *)`
- `Bash(git branch *)`
- `Bash(git check-ignore *)`
- `Bash(git checkout *)`
- `Bash(git cherry-pick *)`
- `Bash(git commit *)`
- `Bash(git describe *)`
- `Bash(git diff *)`
- `Bash(git fetch *)`
- `Bash(git for-each-ref *)`
- `Bash(git log *)`
- `Bash(git ls-files *)`
- `Bash(git ls-remote *)`
- `Bash(git ls-tree *)`
- `Bash(git merge *)`
- `Bash(git name-rev *)`
- `Bash(git pull *)`
- `Bash(git push *)`
- `Bash(git range-diff *)`
- `Bash(git remote *)`
- `Bash(git rev-list *)`
- `Bash(git rev-parse *)`
- `Bash(git rm *)`
- `Bash(git shortlog *)`
- `Bash(git show *)`
- `Bash(git stash *)`
- `Bash(git status *)`
- `Bash(git switch *)`
- `Bash(git tag *)`
- `Bash(git worktree *)`

### Go (build, test, and lint only)

`go run`, `go get`, and `go install` require prompting as they execute
or download code. Bare `go mod tidy` (no args) needs its own entry since
`go mod tidy *` only matches when arguments follow.

- `Bash(go build *)`
- `Bash(go doc *)`
- `Bash(go env *)`
- `Bash(go fmt *)`
- `Bash(go list *)`
- `Bash(go mod tidy)`
- `Bash(go mod tidy *)`
- `Bash(go test *)`
- `Bash(go tool cover *)`
- `Bash(go version *)`
- `Bash(go vet *)`
- `Bash(go-mod-outdated *)`
- `Bash(gofmt *)`
- `Bash(goimports *)`
- `Bash(golangci-lint *)`
- `Bash(govulncheck *)`

### Java / JVM (specific safe goals only)

Catch-all `gradle *` and `mvn *` removed — both can execute arbitrary
tasks. Only known-safe build/test/check goals are allowed.

- `Bash(gradle build *)`
- `Bash(gradle check *)`
- `Bash(gradle dependencies *)`
- `Bash(gradle test *)`
- `Bash(java -version *)`
- `Bash(mvn compile *)`
- `Bash(mvn dependency:tree *)`
- `Bash(mvn test *)`
- `Bash(mvn validate *)`

### JavaScript / Node (run scripts and query only)

`npm install`, `node *` (arbitrary execution), and bare `npx *` (downloads
and runs arbitrary packages) require prompting. Specific `npx <tool>`
forms for known-safe packages are allowed individually — `playwright`
(test runner) and `slidev` (slide dev server). Add new ones explicitly
when friction surfaces; don't re-broaden to bare `npx *`.

- `Bash(eslint *)`
- `Bash(knip *)`
- `Bash(npm list *)`
- `Bash(npm outdated *)`
- `Bash(npm run *)`
- `Bash(npm test *)`
- `Bash(npm-check-updates *)`
- `Bash(npx playwright *)`
- `Bash(npx slidev *)`
- `Bash(pnpm list *)`
- `Bash(pnpm outdated *)`
- `Bash(pnpm run *)`
- `Bash(pnpm test *)`
- `Bash(yarn list *)`
- `Bash(yarn outdated *)`
- `Bash(yarn run *)`
- `Bash(yarn test *)`

### PHP

`composer install`/`composer require` require prompting as they modify
dependencies.

- `Bash(composer list *)`
- `Bash(composer show *)`
- `Bash(composer validate *)`
- `Bash(php-cs-fixer *)`
- `Bash(phpstan *)`

### .NET (build, test, and format only)

`dotnet run`, `dotnet publish`, and `dotnet add` require prompting.

- `Bash(dotnet build *)`
- `Bash(dotnet format *)`
- `Bash(dotnet --info *)`
- `Bash(dotnet --version *)`
- `Bash(dotnet test *)`

### Python (linting and testing only)

`python *`/`python3 *` (arbitrary execution) and `pip install`
(installs packages) require prompting. Linters and test runners are safe.

- `Bash(bandit *)`
- `Bash(deptry *)`
- `Bash(mypy *)`
- `Bash(pip list *)`
- `Bash(pip-audit *)`
- `Bash(pylint *)`
- `Bash(pytest *)`
- `Bash(ruff *)`
- `Bash(vulture *)`

### Ruby

`gem install` and `bundle install` require prompting. Linters and
security scanners are safe.

- `Bash(brakeman *)`
- `Bash(bundle-audit *)`
- `Bash(rubocop *)`

### Rust (build, test, and lint only)

`cargo run`, `cargo install`, and `cargo publish` require prompting.

- `Bash(cargo audit *)`
- `Bash(cargo bench *)`
- `Bash(cargo build *)`
- `Bash(cargo check *)`
- `Bash(cargo clippy *)`
- `Bash(cargo doc *)`
- `Bash(cargo fmt *)`
- `Bash(cargo deny *)`
- `Bash(cargo outdated *)`
- `Bash(cargo test *)`
- `Bash(cargo udeps *)`

### Terraform

- `Bash(checkov *)`
- `Bash(terraform fmt *)`
- `Bash(terraform init *)`
- `Bash(terraform output *)`
- `Bash(terraform plan *)`
- `Bash(terraform state list *)`
- `Bash(terraform validate *)`
- `Bash(tflint *)`
- `Bash(tfsec *)`

### Linting and formatting (cross-language)

- `Bash(actionlint *)`
- `Bash(cspell *)`
- `Bash(lychee *)`
- `Bash(markdownlint *)`
- `Bash(markdownlint-cli2 *)`
- `Bash(pre-commit *)`
- `Bash(prettier *)`
- `Bash(shellcheck *)`
- `Bash(shfmt *)`
- `Bash(yamllint *)`

### TypeScript

- `Bash(tsc *)`

### Security scanning

- `Bash(gitleaks *)`
- `Bash(semgrep *)`
- `Bash(trivy *)`

### PDF processing

- `Bash(ocrmypdf *)`
- `Bash(pandoc *)`
- `Bash(pdfinfo *)`
- `Bash(pdftotext *)`
- `Bash(weasyprint *)`

### Steampipe (read-only cloud queries)

- `Bash(steampipe *)`

### Hugo (static site generator)

- `Bash(hugo *)`

### macOS utilities (read-only)

- `Bash(defaults find *)`
- `Bash(defaults read *)`
- `Bash(sips *)`

### Make (specific safe targets only)

Catch-all `make *` is not allowed — it executes arbitrary targets.
Only known-safe build/lint goals are permitted.

- `Bash(make build)`
- `Bash(make lint)`

### Shell utilities (read-only)

`curl` (can exfiltrate data) and `chmod` (changes permissions) require
prompting. `command -v` and `which` are both allowed — they are POSIX
equivalents for tool-availability checks, and compound commands like
`command -v X && X --version` need the leading `command -v` matched
separately.

- `Bash(awk *)`
- `Bash(command -v *)`
- `Bash(cp *)`
- `Bash(diff *)`
- `Bash(echo *)`
- `Bash(find *)`
- `Bash(grep *)`
- `Bash(jq *)`
- `Bash(ls *)`
- `Bash(lsof *)`
- `Bash(mkdir *)`
- `Bash(pgrep *)`
- `Bash(sed *)`
- `Bash(wc *)`
- `Bash(which *)`

### Process management

Threat model: process kills affect running processes only — not files,
not credentials, not privilege boundaries (the agent already runs as
the user). Worst case is killing the wrong process, which is "annoying"
(restart a dev server, lose unsaved terminal scratch) but never silent
or unrecoverable. The friction relief from not approving every
`pkill -9 -f "<name>"` is worth the recoverable blast radius.

- `Bash(kill *)`
- `Bash(pkill *)` — subsumes `pkill -f *`

### Network diagnostics (read-only)

Port-reachability probes, DNS lookups, and SSH config/auth diagnostics.
All are read-only: `nc -zv` / `nc -uvz` are pure port probes (the `-z`
zero-I/O flag prevents sending data; the `-u` variant probes UDP), `dig`
and `host` are DNS queries, `ssh -G` dumps resolved SSH config without
connecting, and `ssh -o BatchMode=yes -T` is an auth test only (the `-T`
disables PTY allocation so remote command execution is impossible).
`curl` is deliberately NOT listed here — it can exfiltrate data via
arbitrary POSTs (and `curl -s -H 'Authorization: Bearer …'` likewise
remains in the Never Allow list).

- `Bash(dig *)`
- `Bash(host *)`
- `Bash(nc -uvz *)`
- `Bash(nc -zv *)`
- `Bash(ssh -G *)`
- `Bash(ssh -o BatchMode=yes -T *)`

### GitHub MCP server

The GitHub MCP server (`github/github-mcp-server`) provides structured
API access without shell escaping issues. Configured per-machine via
`claude mcp add` (stored in `~/.claude.json`, not in dotfiles). The
permissions below control which MCP tools are auto-approved.

**Read tools** (all auto-approved):

- `mcp__github__get_commit`
- `mcp__github__get_file_contents`
- `mcp__github__get_latest_release`
- `mcp__github__get_me`
- `mcp__github__get_release_by_tag`
- `mcp__github__get_tag`
- `mcp__github__get_team_members`
- `mcp__github__get_teams`
- `mcp__github__issue_read`
- `mcp__github__list_branches`
- `mcp__github__list_commits`
- `mcp__github__list_issues`
- `mcp__github__list_pull_requests`
- `mcp__github__list_releases`
- `mcp__github__list_tags`
- `mcp__github__pull_request_read`
- `mcp__github__search_code`
- `mcp__github__search_issues`
- `mcp__github__search_pull_requests`
- `mcp__github__search_repositories`
- `mcp__github__search_users`

**Write tools** (selectively auto-approved):

- `mcp__github__add_comment_to_pending_review`
- `mcp__github__add_issue_comment`
- `mcp__github__add_reply_to_pull_request_comment`
- `mcp__github__create_branch`
- `mcp__github__create_or_update_file`
- `mcp__github__create_pull_request`
- `mcp__github__issue_write`
- `mcp__github__push_files`
- `mcp__github__sub_issue_write`
- `mcp__github__update_pull_request`
- `mcp__github__update_pull_request_branch`

**Write tools left to prompt** (not in allowedTools):
`create_repository`, `delete_file`, `fork_repository`,
`merge_pull_request` (see Never Allow), `pull_request_review_write`.

### Google Developer Knowledge MCP server (read-only)

- `mcp__google-developer-knowledge__answer_query`
- `mcp__google-developer-knowledge__get_documents`
- `mcp__google-developer-knowledge__search_documents`

### Read permissions (config files)

Auto-approve reading config files accessed during every `/retrospective`
run. Write/Edit access remains gated.

- `Read(~/.claude/retros.md)`
- `Read(~/.claude/settings.json)`

### File-write permissions (scratch space)

**Use `Edit(path)`, never `Write(path)`.** Path-scoped `Write(...)`
rules are not consulted by the file permission check at all — only
`Edit(...)` rules are, and an `Edit` rule covers *every* file-editing
tool, `Write` included. A `Write(...)` rule is therefore dead config:
it grants nothing and the CLI prints a warning about it on every
start. This bit us for months — the two rules below were written as
`Write(...)`, silently granted nothing, and the resulting prompts were
misdiagnosed as a `/tmp` symlink problem (see the `/private/tmp` note
below).

`/tmp` on macOS is per-user, ephemeral, and the standard scratch space —
nothing durable or shared lives there. The blast radius of allowing
writes is "Claude can scribble in scratch space," which is exactly
what scratch space is for.

User-level CLAUDE.md forbids heredocs (`cat <<'EOF'`) and ANSI-C
quoting in bash commands, so any multi-line content for `gh issue
create --body-file`, `gh pr create --body-file`, etc. has to flow
through a temp file. Auto-approving `Edit(/tmp/**)` removes the
double-prompt friction (one for the command, one for the temp file)
that otherwise discourages the structured-body pattern.

- `Edit(/tmp/**)` — scratch space for staging long, structured content
  (issue bodies, PR bodies, etc.) before passing to a CLI via
  `--body-file` or `$(cat ...)`. Restrict scope further to
  `Edit(/tmp/claude-*)` (with a naming-convention discipline) if the
  broad rule ever feels uncomfortable.
- `Edit(/private/tmp/**)` — the same grant, spelled the way macOS
  resolves it. `/tmp` is a symlink to `/private/tmp` there, and paths
  reach the permission check already resolved (the session scratchpad
  is handed to Claude as `/private/tmp/claude-<uid>/...`), so the
  `/tmp/**` glob alone can miss. Both spellings are kept: Linux has no
  such symlink and uses the `/tmp/**` form.

**Removed: `Edit(~/dev/paul-context/_incoming/**)`.** This granted the
journal-draft inbox for the cross-repo retrospective skill, naming one
machine's layout. #300 taught that skill to discover a `paul-context`
checkout wherever it sits, which left the rule covering only the
conventional location — so a retro standing in a checkout anywhere else
(a cloud session has it at `/home/user/paul-context`) picked the
filesystem route and only then hit the allow rules. Interactively that
is a prompt; headless it is a denial with no recovery, because the
skill's guard is `[ -w "<pc>/_incoming" ]` — a *filesystem* writability
test, not a permission test — so the Issue fallback had already been
skipped by the time the write failed, and the retro's whole output was
lost at the last step (#303).

The fix is in the skill, not in a broader rule. `/retrospective` now
stages every draft to `/tmp/<filename>` first and copies it into
`<pc>/_incoming/` from there, so the only write path is one that
`Edit(/tmp/**)` and `Bash(cp *)` already cover — on any checkout root,
on any surface — and a failed copy falls through to the Issue route
with the draft still on disk. That makes this rule dead config, and a
rule granting nothing is worse than no rule: it reads as coverage.

The alternative was broadening the glob to something like
`Edit(**/paul-context/_incoming/**)`. Not taken, because whether a
leading `**/` is honoured by the permission matcher is unverified —
the three surviving `Edit` rules are all anchored absolute paths, and
the `/tmp` vs `/private/tmp` pair above is this file's own precedent
for enumerating spellings rather than trusting the matcher to unify
them. Staging through `/tmp` sidesteps the question entirely.

Unchanged: `_incoming/` is `.gitignored` in `paul-context`, so drafts
are local-only until `/promote-journal-inbox` drains them into
`journal/`; that command runs from a `paul-context` checkout, wherever
it sits. See
`paul-context/decisions/2026-05-05-journal-inbox-promotion.md` for the
full rationale.

## Never allow

These tools have been explicitly reviewed and rejected for auto-approval.
Do not add them in future retrospectives — the decision is final unless
the user revisits it.

| Pattern | Reason |
| ------- | ------ |
| `Bash(python3 *)` / `Bash(python *)` | Arbitrary code execution — too broad |
| `Bash(go run *)` | Arbitrary code execution — same shape as `python *` |
| `Bash(curl *)` / `Bash(curl -s *)` / `Bash(curl -s -H Authorization: Bearer*)` | Can exfiltrate data to arbitrary endpoints; auth-header + URL form is especially dangerous |
| `Bash(yq *)` | `yq -i` mutates files in place — flag isn't constrainable here |
| `Bash(bq query --use_legacy_sql=false*)` | Flag doesn't constrain to SELECT; can run DDL/DML |
| `Bash(gcloud storage cp *)` | Write operation — uploads to GCS |
| `Bash(gcloud run services update-traffic *)` | Mutates production Cloud Run traffic |
| `Bash(gcloud secrets versions access *)` | Reads secret values — credential-exfiltration risk |
| `Bash(gcloud auth print-access-token *)` / `Bash(gcloud auth print-identity-token *)` | Prints a live credential to stdout, i.e. into the transcript and therefore into model context — the exact exfiltration path the credential broker exists to close. `home/commands/gcp-credentials.md` forbids running these in bold ("Never run `gcloud auth print-access-token`"), so auto-approving them made the forbidden action the frictionless one on every local machine. Removed 2026-08; do not re-add |
| `Bash(gcloud monitoring *)` / `Bash(gcloud beta monitoring *)` / `Bash(gcloud alpha monitoring *)` | Can modify alerts and dashboards, not read-only |
| `Bash(gh api *)` / `Bash(gh api repos/*)` | Full GitHub API including POST/PATCH/DELETE — prefer `mcp__github__*` |
| `Bash(gh repo create *)` | Creates repositories — infrequent, should always prompt |
| `Bash(gh pr merge *)` / `mcp__github__merge_pull_request` | PRs should be merged manually, never by Claude Code |

## Hooks

Every hook below is also declared in `home/hooks/hooks.json`, which is what
carries them to a cloud session — see "Two channels, one set of hooks" at the
end of this section for how the two copies avoid running twice.

### PreToolUse (Bash)

1. **pr-checks registration-race rewrite** —
   `~/.claude/bin/prchecks-wait-claude-hook`. Rewrites
   `gh pr checks ... --watch` commands (via `hookSpecificOutput.updatedInput`,
   which replaces the tool's arguments before execution) to run through
   `~/.claude/bin/gh-pr-checks-wait`. The wrapper polls until GitHub has
   registered at least one check run (5s interval, ~2 min cap), then execs
   the real `gh pr checks` with the original arguments. 10s timeout — the
   hook itself only inspects and rewrites; the waiting happens in the
   rewritten command.

   Why: check runs register a variable 0-60s+ after `gh pr create`, and
   `--watch` treats "no checks yet" as terminal ("no checks reported")
   rather than pending — gh has no native wait-for-registration flag. A
   deterministic rewrite beats a prose note that gets skipped under
   momentum, and attaching the wait to the *checking* side (only when
   `--watch` is present) beats a fixed sleep after `pr create`, which
   penalises every PR creation and can still lose the race.

   Fail-open/no-op when: the command isn't `gh pr checks ... --watch`,
   it's already wrapped (never rewrites twice), `jq` is missing, or the
   wrapper isn't deployed yet (fresh machine before `chezmoi apply`).
   The wrapper itself gives up early (3 consecutive probe errors that
   aren't "no checks reported" — bad selector, offline, auth) and always
   falls through to the real command, so the worst case is gh's own error,
   never a hang. The companion allow rule
   `Bash(~/.claude/bin/gh-pr-checks-wait *)` keeps the rewritten command
   auto-approved, matching the existing `Bash(gh pr checks *)` grant.

2. **PR-state push guard** — `~/.claude/bin/prepush-guard-claude-hook`.
   Before any `git push` Claude makes, asks GitHub (`gh pr view <branch>`)
   whether the current branch's PR is already `MERGED`/`CLOSED`, and if so
   **blocks** with `exit 2` and instructions to start a fresh branch. 30s
   timeout.

   This enforces mechanically what the CLAUDE.md prose rule ("check the PR is
   still open before pushing follow-up commits") failed to: the user merges a
   PR via the GitHub UI mid-session, the branch auto-deletes, and the next
   push silently recreates it as an orphan — `* [new branch]` in unread output
   is the only tell, and recovery costs a cleanup cycle. GitHub is the
   authority because local state is useless here: the stale remote-tracking
   ref survives the remote deletion until a `fetch --prune`.

   **Fail-open by design** — the guard stops one specific silent mistake
   without making pushing fragile. It allows the push when: the command isn't
   a `git push`; `--no-verify` is present (escape hatch, e.g. deliberately
   recreating a branch); the push is `--delete`/`-d` or `--tags`; `gh` or
   `jq` is missing; HEAD is detached; the branch is the default branch; the
   branch has no PR; the PR is open; or the lookup fails for any reason
   (offline, auth). `gh pr view` prefers an open PR when one exists, so
   re-using a branch name under a new PR is not a false positive. Limitation:
   it inspects the **current** branch — a push naming a different refspec is
   waved through.

3. **pre-commit lint gate** — `~/.claude/bin/precommit-claude-hook`. A single
   script that runs the pre-commit framework against the repo's
   `.pre-commit-config.yaml` on the `git commit` / `git push` commands Claude
   makes via its Bash tool, **blocking** on failure with `exit 2` (the only
   PreToolUse exit code that both stops the tool call and feeds stderr back to
   Claude — `exit 1` and other non-zero codes are non-blocking). 120s timeout.

   This is the global replacement for the commit/push-stage hooks that
   `init.templatedir` git-templates used to install per-repo — part of the
   vanilla-git migration that removed those templates.

   Two stages:
   - `git commit` → `--hook-stage pre-commit` on the **staged delta** (fast;
     correct commit-stage semantics). Falls back to `--all-files` for
     `git commit -a`/`--all`, where git stages files *after* the hook fires.
   - `git push` → `--hook-stage pre-push --all-files` (whole-tree backstop
     before CI; also covers manual / `--no-verify` commits the commit stage
     never saw).

   **Silent on success:** output is captured and emitted only on failure, so
   passing checks add nothing to the transcript or to context. Fast-exits
   (no-op) when: the command isn't a `git commit`/`git push`, `--no-verify`/`-n`
   is present, no `.pre-commit-config.yaml` exists, or `pre-commit` isn't
   installed. Only governs commands Claude runs via its Bash tool — manual
   terminal commits/pushes are CI-backed.

### PostToolUse (Write|Edit)

1. **terraform fmt** — Auto-formats `.tf` files after every Write or Edit.
   Parses the file path from hook stdin JSON via `jq`, skips non-`.tf` files.

2. **terraform validate** — Validates the module directory after `.tf` file
   changes. Only runs if `.terraform/` exists in the file's directory
   (i.e., `terraform init` has been run). 30s timeout.

Both are written in POSIX `sh` (`case`, not `[[ ]]`) and lead with
`command -v terraform || exit 0`. The bash-only test was fine on a workstation
and silently never matched under `dash`, which is what a Linux sandbox is
likely to run these with; the `command -v` guard keeps a sandbox that edits a
`.tf` file from emitting "terraform: not found" on every Write.

### Two channels, one set of hooks

The same five hooks are declared twice: here, for the chezmoi deployment, and
in `home/hooks/hooks.json`, for the plugin. Claude Code runs every matching
hook from every source, so a local machine working in a repo that has enabled
the plugin has both live at once — and `precommit-claude-hook` running
pre-commit twice on every commit is up to 120s of duplicated work on the
hottest path there is.

The three script hooks therefore go through `bin/plugin-hook-dispatch` in the
plugin copy. It stands down when `~/.claude/bin/<hook>` exists, so **the
chezmoi copy wins wherever it is deployed** — which is also the copy the
`Bash(~/.claude/bin/gh-pr-checks-wait *)` allow rule below is written for.
That rule holds through the #142 transition in either order: a machine on an
old `settings.json` with the plugin already enabled runs each hook once via
chezmoi, and a machine whose `bin/` has been pruned runs each hook once via
the plugin. Never twice, never zero.

The two terraform hooks are inline commands rather than scripts, so they have
no dispatcher and do run twice where both channels are live. Accepted: `fmt`
is idempotent and instant, `validate` re-reads a module that is already
initialised, and both no-op entirely without terraform on PATH.

`prchecks-wait-claude-hook` resolves its wrapper as
`$(dirname "$0")/gh-pr-checks-wait` rather than at a fixed `~/.claude/bin`
path, which is what lets one file serve both channels. Note the consequence
for permissions: from the plugin the rewritten command names a path under the
plugin root, which this allowlist cannot match — cloud sessions read their
permissions from the project repo's own `.claude/settings.json`, so that is
where the grant has to be if the rewrite is to stay auto-approved there.

## StatusLine

Custom status line rendered by [cship](https://github.com/stephenleo/cship)
(v1.4.1, pinned to commit `1e5940e`). Claude Code pipes session JSON to
cship's stdin on every render cycle; cship outputs styled ANSI text for
the TUI status bar.

Config lives at `~/.config/cship.toml`. Usage limits module is disabled
(credential access not needed — `/usage` and the built-in 90% warning
are sufficient).

```json
"statusLine": {
  "type": "command",
  "command": "cship"
}
```

On machines without `cship` installed, Claude Code silently falls back
to the default status line.
