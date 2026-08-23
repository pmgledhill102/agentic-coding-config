#!/bin/sh
# bootstrap.sh — install this repo's agent toolkit into a cloud sandbox.
#
# The one line a Claude Code cloud environment's setup script holds, so that
# everything of substance stays here, versioned, instead of being pasted into a
# vendor configuration field (ADR-0016, principle 5):
#
#   curl -sSL https://raw.githubusercontent.com/pmgledhill102/agentic-coding-config/<REF>/cloud/bootstrap.sh | sh -s -- <REF> [--with-gcloud] [--with-precommit] [--with-hooks] [--with-gh] [--profile <name>]
#
# --with-gcloud installs the Google Cloud SDK as well. Opt-in, so that the one
# line an environment carries declares what kind of environment it is.
#
# --with-precommit installs the pre-commit framework and the binaries this
# estate's hooks need, and points git at a global hook so every repo in the
# container is covered. Opt-in for the same reason, and one more: it is the only
# part of this script that needs the Ubuntu archives, so an environment that
# cannot reach them keeps working by not asking for it.
#
# --with-hooks wires this estate's PreToolUse guards and PostToolUse terraform
# hooks into ~/.claude/settings.json. Separate from --with-precommit because
# they are different mechanisms: a git hook blocks the commit, a harness hook
# returns the failure into the agent's context where it can act on it.
#
# --with-gh installs the GitHub CLI from a pinned release tarball, for the
# session skills' gather scripts. NOT for Anthropic-hosted web sandboxes:
# there the egress proxy authenticates gh for identity endpoints only and
# 403s every repo-scoped API path, so the gather sections come back
# gh-unauthorized rather than populated — measured 2026-08-19, lane map on
# #257, cleanup on #273. The flag exists for surfaces whose egress genuinely
# reaches the GitHub API, e.g. self-hosted environments.
#
# --profile names the composed context profile to install, defaulting to
# claude-cloud-sandbox. A Codex environment passes --profile codex-cloud-sandbox.
# The environment declares which harness it is rather than this script sniffing
# for one: ADR-0018 principle 1 puts surface differences in the delivery, and
# the caller is the only party that knows the answer without guessing.
#
# Pass the same <REF> twice on purpose: the first fetches this script, the
# second is what it fetches everything else from, so a run cannot straddle two
# versions. Pin <REF> to a tag or commit in anything durable — a branch means
# any compromise of this repo reaches every sandbox that starts afterwards.
#
# This script fails loudly: a half-installed toolkit is worse than none, and the
# caller is better placed to decide tolerance. A cloud setup script, which fails
# the whole session on a non-zero exit, should append `|| true`.
#
# It installs no credentials and reads none. What it places is public content
# from a public repo.

set -eu

log() { echo "[bootstrap] $*"; }
die() { echo "[bootstrap] error: $*" >&2; exit 1; }

REF="${1:-main}"
[ $# -gt 0 ] && shift
WITH_GCLOUD=0
WITH_PRECOMMIT=0
WITH_HOOKS=0
WITH_GH=0
PROFILE=claude-cloud-sandbox

while [ $# -gt 0 ]; do
    case "$1" in
        --with-gcloud) WITH_GCLOUD=1 ;;
        --with-precommit) WITH_PRECOMMIT=1 ;;
        --with-hooks) WITH_HOOKS=1 ;;
        --with-gh) WITH_GH=1 ;;
        --profile)
            shift
            [ $# -gt 0 ] || die "--profile needs a value"
            PROFILE="$1"
            ;;
        --profile=*) PROFILE="${1#--profile=}" ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

RAW="https://raw.githubusercontent.com/pmgledhill102/agentic-coding-config/${REF}"

command -v curl > /dev/null 2>&1 || die "curl is required"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

log "installing from ${REF}"

# There is deliberately no apt step here.
#
# An earlier draft installed curl, ca-certificates and openssl defensively, on
# the reasoning that the documented list of pre-installed tools does not mention
# curl. That list summarises rather than enumerates, and the sandbox image
# carries curl 8.5.0 against OpenSSL 3.0.13 — verified, not inferred. A working
# TLS fetch of this script proves ca-certificates too, since it could not have
# arrived otherwise.
#
# openssl was speculative convenience: nothing here uses it. Installing packages
# on a guess costs an apt-get update on every cache rebuild, needs the Ubuntu
# archives reachable, and bakes an assumption into a snapshot where nobody will
# revisit it. A task that genuinely needs a package can install it, having
# established that it is missing.
#
# --with-precommit does apt-get, which is not a reversal of that. The objection
# above is to installing on a *guess*; a hook declared in a repo's committed
# .pre-commit-config.yaml that cannot run without shellcheck is a demonstrated
# dependency. It stays behind a flag so the archive requirement is opted into
# rather than imposed on every environment.

# --- gcloud, on request -------------------------------------------------------
#
# Opt-in, because a repo with no GCP work should not pay a 96 MB download, and
# because an environment naming --with-gcloud in its one line is declaring what
# kind of environment it is. That is the capability-profile model ADR-0016
# describes, made visible in the place the choice is actually made.
#
# It must land BEFORE the first `gcp-credentials request`: the helper wires up a
# gcloud configuration only if gcloud is on PATH at that moment. Installed
# afterwards, the token file ends up with nothing pointing at it, and correcting
# that costs a second human approval.

if [ "$WITH_GCLOUD" -eq 1 ] && ! command -v gcloud > /dev/null 2>&1; then
    curl -sSL -o "$TMP/gcloud.tar.gz" \
        https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz ||
        die "could not download the gcloud SDK — is dl.google.com on the allowlist?"
    tar -xzf "$TMP/gcloud.tar.gz" -C /opt || die "could not unpack the gcloud SDK"
    # --path-update false, then symlink: a PATH line appended to a shell profile
    # is not reliably sourced by the non-interactive shells tool calls run in.
    /opt/google-cloud-sdk/install.sh --quiet --usage-reporting false \
        --path-update false --command-completion false > /dev/null || true
    # A wrapper rather than a symlink, because the sandbox image presets
    # CLOUDSDK_AUTH_ACCESS_TOKEN and that variable outranks the
    # auth/access_token_file the broker configures. Every call then fails
    # ACCESS_TOKEN_TYPE_UNSUPPORTED while the helper, `status` and the token file
    # all report healthy — confirmed in two independent fresh sandboxes.
    #
    # The documented workaround is `env -u CLOUDSDK_AUTH_ACCESS_TOKEN` on every
    # invocation, which fails the moment anyone forgets, and fails silently by
    # picking the wrong identity rather than erroring. Better to make the right
    # thing the default.
    #
    # Narrow on purpose: it drops the variable only when a broker token actually
    # exists. With no grant installed, the preset token is whatever the sandbox
    # intended and is left alone.
    cat > /usr/local/bin/gcloud << 'WRAPPER'
#!/bin/sh
# Installed by agentic-coding-config cloud/bootstrap.sh.
#
# Two jobs, both because gcloud otherwise gets the wrong credential:
#
#   1. Prefer a broker-issued token over the sandbox image's preset
#      CLOUDSDK_AUTH_ACCESS_TOKEN, which outranks auth/access_token_file.
#   2. Re-mint a stale token before the call, rather than relying on a
#      background loop that this environment reaps.
#
# The second replaces a daemon with a check. Detached refresh loops die here --
# twice in one session, once across an idle gap and once during active work --
# and when they do the grant stays valid for days while the token quietly ages
# out. Checking an mtime at the point of use has nothing to keep alive and
# nothing to reap, and it covers gcloud called from inside a script, which a
# session hook never sees.
CB_HOME="${CREDENTIAL_BROKER_HOME:-$HOME/.config/claude/credential-broker}"
CB_TOKEN="$CB_HOME/access_token"

# The threshold is really a floor on how much token life a call can start with:
# a token renewed at age T has 3600 - T seconds left, so T is chosen from how
# long a single invocation might run.
#
# 1800 against a 3600s token guarantees 30 minutes in hand. Observed scripts
# here run 10-25 minutes, which 2700 would have failed -- it leaves as little as
# 15. The extra renewals cost one HTTP call each and are not worth optimising.
#
# A script that calls gcloud repeatedly is covered for any duration, because
# every invocation re-checks and renews when stale. What this cannot save is a
# *single* call that blocks longer than the remaining life: Apigee provisioning
# at 70-80 minutes will still expire mid-flight and need re-running. That is
# accepted rather than solved, and it is why the floor matters more than the
# ceiling.
CB_MAX_AGE="${CREDENTIAL_BROKER_MAX_TOKEN_AGE:-1800}"

# CB_NO_RENEW stops a renew that shells out to gcloud from recursing. It does
# not today, but a wrapper that can loop forever is not worth the risk.
if [ -f "$CB_TOKEN" ] && [ -z "${CB_NO_RENEW:-}" ]; then
    cb_now=$(date +%s)
    cb_mtime=$(stat -c %Y "$CB_TOKEN" 2> /dev/null || stat -f %m "$CB_TOKEN" 2> /dev/null || echo "$cb_now")
    if [ $((cb_now - cb_mtime)) -ge "$CB_MAX_AGE" ]; then
        cb_helper=$(command -v gcp-credentials 2> /dev/null || echo "$HOME/.claude/bin/gcp-credentials")
        if [ -x "$cb_helper" ]; then
            # Quiet on success: this runs before an unrelated command and must
            # not pollute output a script may be parsing. Failure is worth a
            # line, but is not fatal here -- gcloud reports its own auth error
            # better than a wrapper can guess at one.
            CB_NO_RENEW=1 "$cb_helper" renew > /dev/null 2>&1 ||
                echo "gcloud: broker token is stale and renew failed; run 'gcp-credentials status'" >&2
        fi
    fi
fi

if [ -n "${CLOUDSDK_AUTH_ACCESS_TOKEN:-}" ] && [ -f "$CB_TOKEN" ]; then
    exec env -u CLOUDSDK_AUTH_ACCESS_TOKEN /opt/google-cloud-sdk/bin/gcloud "$@"
fi
exec /opt/google-cloud-sdk/bin/gcloud "$@"
WRAPPER
    chmod 0755 /usr/local/bin/gcloud || true
    ln -sf /opt/google-cloud-sdk/bin/gsutil /usr/local/bin/gsutil || true
    log "gcloud  -> $(gcloud --version 2> /dev/null | head -1 || echo 'installed')"
elif [ "$WITH_GCLOUD" -eq 1 ]; then
    log "gcloud  : already present, left alone"
fi

# --- the helper --------------------------------------------------------------
#
# /usr/local/bin when writable, which is the case in a sandbox running as root,
# so the helper is on PATH for every shell without touching a profile. Falling
# back to ~/.local/bin keeps this usable unprivileged, where PATH may need help.

if [ -w /usr/local/bin ] 2> /dev/null; then
    BIN_DIR=/usr/local/bin
else
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
fi

curl -sSfL "$RAW/home/bin/gcp-credentials" -o "$TMP/gcp-credentials" ||
    die "could not fetch the helper from $REF"
# Refuse an error page rendered as a script. A 404 from a bad ref is HTML, and
# `sh` would run it and report something baffling.
head -1 "$TMP/gcp-credentials" | grep -q '^#!' ||
    die "fetched helper is not a script — check that $REF exists"

install -m 0755 "$TMP/gcp-credentials" "$BIN_DIR/gcp-credentials"
log "helper  -> $BIN_DIR/gcp-credentials"

# The skill still spells its invocations ~/.claude/bin/gcp-credentials, because
# that is where chezmoi puts the helper on a laptop. Nothing here creates that
# path, so an agent following the documented command would hit "no such file"
# next to a perfectly good helper on PATH — or worse, find a stale vendored copy
# there and run that instead. Symlink until the skill stops naming a path at
# all, which is the real fix and is the corollary in ADR-0016 principle 3:
# delivery assumptions do not belong in portable text.
mkdir -p "$HOME/.claude/bin"
ln -sf "$BIN_DIR/gcp-credentials" "$HOME/.claude/bin/gcp-credentials"
log "compat  -> $HOME/.claude/bin/gcp-credentials -> $BIN_DIR/gcp-credentials"

# --- the skill: one file, vendor paths as adapters ----------------------------
#
# The canonical copy goes to ~/.agents/skills, the vendor-neutral Agent Skills
# location that Codex, OpenCode and Gemini CLI scan natively. Claude Code does
# not read it — its documentation names only ~/.claude/skills and
# .claude/skills — so ~/.claude/skills gets a symlink pointing at the real
# thing.
#
# That direction is deliberate. Copying into each vendor's directory would work
# and would reintroduce the one failure this repo keeps meeting: two copies of
# the same content, diverging quietly. A symlink cannot drift, and a fourth
# provider costs another link rather than another copy. It is also ADR-0016
# principle 3 in the filesystem — the portable path holds the content, the
# vendor path is a thin adapter — rather than a paragraph asserting it.
#
# That a container-created ~/.claude/skills is read at all is no longer an open
# question: a sandbox session on 2026-08-13 discovered this skill there and
# invoked it unprompted. What a symlinked skill directory does is the part still
# worth watching; if Claude stops listing the skill, that is why.

curl -sSfL "$RAW/home/commands/gcp-credentials.md" -o "$TMP/gcp-credentials.md" ||
    die "could not fetch the skill from $REF"

# SKILL.md wants frontmatter the command format does not carry. The first line
# of the command file is its description by convention, so lift it — single
# quoted, with any internal quote doubled, because that description contains a
# colon and would otherwise be read as a YAML mapping.
SKILL_DIR="$HOME/.agents/skills/gcp-credentials"
mkdir -p "$SKILL_DIR"
DESC=$(head -1 "$TMP/gcp-credentials.md" | sed "s/'/''/g")
{
    echo "---"
    echo "name: gcp-credentials"
    echo "description: '${DESC}'"
    echo "---"
    echo ""
    tail -n +2 "$TMP/gcp-credentials.md"
} > "$SKILL_DIR/SKILL.md"
log "skill   -> $SKILL_DIR/SKILL.md (canonical)"

# An earlier run left a real directory here, and `ln -s` onto one links *inside*
# it rather than replacing it. Remove first; the path is fixed and ours.
rm -rf "$HOME/.claude/skills/gcp-credentials"
mkdir -p "$HOME/.claude/skills"
ln -sfn "$SKILL_DIR" "$HOME/.claude/skills/gcp-credentials"
log "adapter -> $HOME/.claude/skills/gcp-credentials"

# Claude merged custom commands into skills: a commands/*.md and a
# skills/*/SKILL.md both register the same /name and behave the same way. So an
# earlier run's commands copy is now a second, Claude-only registration of a
# skill that already works from the neutral path. Remove it rather than leave
# two sources for one command.
rm -f "$HOME/.claude/commands/gcp-credentials.md"

# --- pre-commit, on request ---------------------------------------------------
#
# Sandboxes bypassed the pre-commit framework entirely: the binary was absent
# and no `.git/hooks/pre-commit` existed, so a repo's committed
# .pre-commit-config.yaml did nothing here (#254). Four consecutive PRs on
# 2026-08-18 were committed with markdownlint, shellcheck and actionlint
# unenforced -- they passed only because a human-equivalent ran them by hand.
#
# This is the vendor-neutral half of enforcement, and the reason it is worth
# doing before the harness-hook half: git runs .git/hooks itself, so nothing
# here depends on agent configuration, on which harness is running, or on the
# unsettled question of whether a container-created ~/.claude/settings.json is
# honoured. It covers Codex, Claude, and a human typing `git commit`, all the
# same way.

if [ "$WITH_PRECOMMIT" -eq 1 ]; then
    # Both linters are `language: system` hooks in this estate's config -- they
    # run the binary on PATH rather than a pinned mirror, so the hook and CI
    # cannot drift to different versions.
    #
    # (Written as "both linters" rather than naming the first one at the start
    # of a comment line: `# shellcheck ...` is parsed as a shellcheck directive
    # and fails the lint, which this script is itself subject to.) That only works if the
    # binaries are here. Installing them is the whole point; SKIP= exists for a
    # laptop missing one, and normalising it would leave enforcement that is
    # routinely skipped, which is not enforcement.
    if ! command -v shellcheck > /dev/null 2>&1; then
        if ! apt-get update -qq > /dev/null 2>&1; then
            die "apt-get update failed — are the Ubuntu archives reachable?"
        fi
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq shellcheck > /dev/null 2>&1; then
            die "could not install shellcheck"
        fi
    fi
    log "shellck -> $(command -v shellcheck)"

    # actionlint is not packaged in Ubuntu, so it comes from a pinned release.
    # Note github.com answers 403 to this sandbox's curl while the release asset
    # itself resolves fine through the redirect -- a naive reachability probe
    # against github.com reads as an egress block and is not one.
    if ! command -v actionlint > /dev/null 2>&1; then
        AL_VER=1.7.7
        curl -sSfL -o "$TMP/actionlint.tar.gz" \
            "https://github.com/rhysd/actionlint/releases/download/v${AL_VER}/actionlint_${AL_VER}_linux_amd64.tar.gz" ||
            die "could not download actionlint ${AL_VER}"
        tar -xzf "$TMP/actionlint.tar.gz" -C "$TMP" actionlint || die "could not unpack actionlint"
        install -m 0755 "$TMP/actionlint" /usr/local/bin/actionlint || die "could not install actionlint"
    fi
    log "actionl -> $(command -v actionlint)"

    command -v pre-commit > /dev/null 2>&1 ||
        pip install --quiet --no-input pre-commit > /dev/null 2>&1 ||
        die "could not install pre-commit from PyPI"
    log "precmit -> $(command -v pre-commit) ($(pre-commit --version))"

    # A GLOBAL hook via core.hooksPath, not `pre-commit install` per repo.
    #
    # `pre-commit install` writes into an existing clone's .git/hooks, and this
    # script runs from an environment setup script whose ordering against the
    # session's clone is not something it can rely on -- the repository may not
    # exist yet, and may not be the only one. core.hooksPath is set once and
    # applies to every repo in the container however and whenever it arrives.
    #
    # The trade-off, stated because it is real: core.hooksPath REPLACES a repo's
    # own .git/hooks rather than adding to it, and `pre-commit install` will warn
    # that it is being overridden. In this estate hooks come from pre-commit
    # anyway, so nothing is lost; a container that needed bespoke per-repo hooks
    # would want the other mechanism.
    HOOK_DIR="$HOME/.config/git/hooks"
    mkdir -p "$HOOK_DIR"
    cat > "$HOOK_DIR/pre-commit" << 'HOOK'
#!/bin/sh
# Installed by agentic-coding-config cloud/bootstrap.sh.
#
# Global pre-commit hook: runs the repo's own pre-commit configuration when it
# has one, and gets out of the way when it does not. A repo with no
# .pre-commit-config.yaml is not opting out of anything -- it simply has no
# configuration to run, and blocking its commits would be this container
# inventing policy the repo never asked for.
[ -f .pre-commit-config.yaml ] || exit 0
command -v pre-commit > /dev/null 2>&1 || exit 0
exec pre-commit run --hook-stage pre-commit
HOOK
    chmod 0755 "$HOOK_DIR/pre-commit"
    git config --global core.hooksPath "$HOOK_DIR"
    log "githook -> $HOOK_DIR/pre-commit (core.hooksPath, all repos)"
fi

# --- gh, on request -----------------------------------------------------------
#
# From a pinned release tarball, exactly like actionlint above: no
# Ubuntu-archive dependency, so an environment that cannot reach the archives
# can still have it, and the version is a decision rather than whatever the
# distro froze. The same 403-vs-redirect note as actionlint applies — a naive
# reachability probe against github.com reads as an egress block and is not
# one.
#
# No auth step, deliberately. These containers carry a GH_TOKEN sentinel the
# egress proxy substitutes with a real credential — but on Anthropic-hosted
# web sandboxes only for identity endpoints (user, rate_limit); every
# repo-scoped API path 403s by policy, which is why the flag is not for that
# surface (#257 lane map, #273). The gather scripts probe once and degrade to
# a gh-unauthorized sentinel there, and pass -R explicitly everywhere rather
# than trusting repo inference behind a proxy.

if [ "$WITH_GH" -eq 1 ] && ! command -v gh > /dev/null 2>&1; then
    GH_VER=2.97.0
    curl -sSfL -o "$TMP/gh.tar.gz" \
        "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_amd64.tar.gz" ||
        die "could not download gh ${GH_VER}"
    tar -xzf "$TMP/gh.tar.gz" -C "$TMP" "gh_${GH_VER}_linux_amd64/bin/gh" ||
        die "could not unpack gh"
    install -m 0755 "$TMP/gh_${GH_VER}_linux_amd64/bin/gh" /usr/local/bin/gh ||
        die "could not install gh"
    log "gh      -> $(gh --version 2> /dev/null | head -1 || echo 'installed')"
elif [ "$WITH_GH" -eq 1 ]; then
    log "gh      : already present, left alone"
fi

# --- the agent policy ---------------------------------------------------------
#
# Until now a sandbox got no policy at all: `ls ~/.claude/*.md` was empty, and
# the 200-odd lines of working policy reached workstations through chezmoi and
# nowhere else. Every session on this surface ran on whatever the opened repo
# happened to commit (#245).
#
# What lands here is a COMPOSED PROFILE, not the raw fragments. ADR-0018
# resolves surface differences at delivery: the sandbox profile is built from
# the portable core, the sandbox environment fragment, and the provider
# fragment, and it deliberately excludes the workstation fragment. That is what
# stops "run chezmoi apply" reaching a container with no chezmoi -- confidently
# wrong policy, which is worse than none. CI fails the build if a workstation
# fragment ever reaches a sandbox profile, so this fetch does not have to
# check.
#
# The file is complete, with no @imports to resolve. That matters for Codex,
# which rejects @file templating: an import here would arrive as literal text
# and the content it named would be lost silently.

PROFILE_DIR="$HOME/.agents"
mkdir -p "$PROFILE_DIR"

curl -sSfL "$RAW/profiles/$PROFILE/AGENTS.md" -o "$TMP/AGENTS.md" ||
    die "could not fetch profile '$PROFILE' from $REF — check the name against profiles/ in the repo"

# Same 404-as-content guard as everything else here: a bad ref or a mistyped
# profile can return an HTML error page with a 200 from some proxies, and
# policy whose first line is <!DOCTYPE reads as a broken agent rather than a
# broken fetch.
head -1 "$TMP/AGENTS.md" | grep -q "^<!-- GENERATED" ||
    die "fetched profile is not a composed artefact — check that $REF and profile '$PROFILE' exist"

cp "$TMP/AGENTS.md" "$PROFILE_DIR/AGENTS.md"
log "policy  -> $PROFILE_DIR/AGENTS.md (profile: $PROFILE)"

# Claude Code reads CLAUDE.md and does not read AGENTS.md, so the Claude
# profiles ship a second composed file for it. A container-created
# ~/.claude/CLAUDE.md is read: verified 2026-08-18 by planting a marker
# mid-session and finding it in context on resume, announced as the user's
# global instructions. The cloud docs list user-scope CLAUDE.md as
# unavailable, but that is about your laptop's copy not being transferred,
# which is a different claim -- the same distinction ADR-0016 already
# established for ~/.claude/skills.
#
# Codex profiles ship AGENTS.md only. Where Codex reads user-level AGENTS.md is
# still unestablished (#176), so ~/.agents/ is where it goes and nothing here
# claims that path is the one Codex reads.
case "$PROFILE" in
    claude-*)
        curl -sSfL "$RAW/profiles/$PROFILE/CLAUDE.md" -o "$TMP/CLAUDE.md" ||
            die "could not fetch the Claude adapter for profile '$PROFILE' from $REF"
        head -1 "$TMP/CLAUDE.md" | grep -q "^<!-- GENERATED" ||
            die "fetched Claude adapter is not a composed artefact"
        mkdir -p "$HOME/.claude"
        cp "$TMP/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
        log "adapter -> $HOME/.claude/CLAUDE.md"
        ;;
esac

# --- the workflow skills ------------------------------------------------------
#
# Everything above installs the credential client. This section is what makes
# the script a config channel rather than a credential one: an explicit list of
# skills that a sandbox should have, fetched by name.
#
# WHY A WHITELIST AND NOT `home/skills/*`: there is no directory listing over
# raw.githubusercontent.com, so a wildcard would need the GitHub API, a token,
# and a JSON parser — three dependencies for a list that changes a few times a
# year. Naming them is also the review point: a skill reaches every sandbox the
# moment it is added here, so the addition should be a decision rather than a
# side effect of creating a file. The 15 `setup-*` skills are deliberately
# absent pending a currency review: they are repo-scaffolding procedures that a
# sandbox session rarely needs, and they predate this surface by some months.
#
# WHY THESE FETCH A PRE-BUILT SKILL.md AND gcp-credentials DOES NOT: the 17
# skills under `home/skills/` are checked in with frontmatter and guarded
# against drifting from their source command by tests/skills-match-commands.py.
# There is nothing to synthesise, so this loop just fetches. The credential
# skill above predates that machinery and is still generated from its command
# file at install time; when it joins `home/skills/` these two paths merge.
#
# TWO LISTS, BECAUSE THERE ARE TWO SOURCES (#265). A composed skill has a
# per-surface body: the sandbox variant calls the GitHub MCP server where the
# workstation variant reads what `gh` put in the gather output, resolved at
# composition rather than by the session working out which half of one text
# applies to it (ADR-0018 principle 1). Its artefact therefore lives under
# profiles/<profile>/skills/, next to that profile's composed policy, and is
# fetched by profile exactly as AGENTS.md and CLAUDE.md are above. A plain
# skill has one body for every surface and still comes from home/skills/.
#
# Adding a composed variant of an existing skill means moving its name from
# SKILLS to COMPOSED_SKILLS in the same change that adds the manifest entry.
# Getting that backwards is caught at install: the fetch 404s and the script
# dies naming the skill, rather than a session quietly running the wrong body.
#
# SKILLS is empty as of #288, which composed the last of the three session
# skills. It stays because the distinction is real and the next skill added
# here is more likely to need one body than two — ADR-0018 principle 8 makes
# that the default, not the exception.

SKILLS=""
COMPOSED_SKILLS="retrospective start-session end-session"

# Helper scripts the session skills shell out to. They are NOT optional: the
# skills invoke them by name, and a skill whose helper is missing fails at the
# point of use rather than at install, which is the worst time to find out.
#
# start-session-claude-drift is here because start-session-gather-state runs it
# as "$(dirname "$0")/start-session-claude-drift" -- a sibling dependency that
# nothing in the skill text mentions, so it would be easy to omit and hard to
# diagnose.
#
# They land in ~/.claude/bin because the skills spell their invocation
# "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/bin/<script>". Under a plugin install
# that variable is set; delivered this way it is not, and the fallback resolves
# here. That dual spelling is why these skills need no edit to work on this
# surface.
BIN_SCRIPTS="start-session-gather-state start-session-claude-drift end-session-gather-state end-session-squash-merged"

# Defensive: the credential-helper section above already creates this, but the
# dependency is invisible from here and a reordering would break it silently.
mkdir -p "$HOME/.claude/bin"

for script in $BIN_SCRIPTS; do
    curl -sSfL "$RAW/home/bin/$script" -o "$TMP/$script" ||
        die "could not fetch helper script $script from $REF"
    head -1 "$TMP/$script" | grep -q '^#!' ||
        die "fetched $script is not a script — check that $REF exists"
    install -m 0755 "$TMP/$script" "$HOME/.claude/bin/$script"
done
log "helpers -> $HOME/.claude/bin/ ($(echo "$BIN_SCRIPTS" | wc -w | tr -d ' ') session scripts)"

for skill in $SKILLS $COMPOSED_SKILLS; do
    # One loop, one difference: where the body comes from. Recomputing it per
    # skill keeps the install, symlink and de-duplication steps below in a
    # single place rather than duplicated per source.
    case " $COMPOSED_SKILLS " in
        *" $skill "*) src="profiles/$PROFILE/skills/$skill/SKILL.md" ;;
        *) src="home/skills/$skill/SKILL.md" ;;
    esac

    curl -sSfL "$RAW/$src" -o "$TMP/$skill.SKILL.md" ||
        die "could not fetch the $skill skill from $REF ($src) — a composed skill needs a profiles/$PROFILE/skills/ entry in context/manifest.json"

    # Same 404-as-content guard as the helper: a bad ref returns an HTML error
    # page with a 200 from some proxies, and a skill whose body is HTML fails
    # in a way that reads like the skill being wrong rather than absent.
    head -1 "$TMP/$skill.SKILL.md" | grep -q '^---$' ||
        die "fetched $skill skill has no frontmatter — check that $REF exists"

    dir="$HOME/.agents/skills/$skill"
    mkdir -p "$dir"
    cp "$TMP/$skill.SKILL.md" "$dir/SKILL.md"

    # Same canonical/adapter split as the credential skill above: the real file
    # lives in the vendor-neutral tree, each vendor path is a symlink that
    # cannot drift. See that comment for the reasoning.
    rm -rf "$HOME/.claude/skills/$skill"
    ln -sfn "$dir" "$HOME/.claude/skills/$skill"
    log "skill   -> $dir/SKILL.md (+ ~/.claude/skills/$skill)"

    # A previous chezmoi-era or hand-copied command file registers the same
    # /name a second time. Same reasoning as gcp-credentials above.
    rm -f "$HOME/.claude/commands/$skill.md"
done

# --- harness hooks, on request ------------------------------------------------
#
# The other half of enforcement. #256 ships the pre-commit framework and a
# native git hook, which blocks a bad commit; these run inside the agent loop
# and return the failure into its context, where it can read the message and
# fix the cause rather than just being stopped. Both are worth having.
#
# Viable because a container-created ~/.claude/settings.json IS honoured --
# measured 2026-08-18 by planting one and watching a PreToolUse hook fire eight
# seconds later, with no session restart (#254). That is the third
# documented-as-unavailable user-scope path to work from inside the container,
# after ~/.claude/skills and ~/.claude/CLAUDE.md.
#
# The wiring is taken from home/settings.json rather than restated here. That
# file is the workstation's, and it already invokes ~/.claude/bin/<hook>
# directly -- the same paths this script installs to -- so the two surfaces run
# identical hooks from one source instead of a copy that drifts.
#
# NOT via plugin-hook-dispatch. That dispatcher exists to stand down when a
# ~/.claude/bin copy is present, because a plugin-enabled workstation would
# otherwise run every hook twice. Here the bootstrap-written copy is the only
# copy, so the settings file names it directly, exactly as chezmoi's does.

if [ "$WITH_HOOKS" -eq 1 ]; then
    command -v jq > /dev/null 2>&1 || die "--with-hooks needs jq to merge settings.json"

    for script in prchecks-wait-claude-hook prepush-guard-claude-hook precommit-claude-hook; do
        curl -sSfL "$RAW/home/bin/$script" -o "$TMP/$script" ||
            die "could not fetch hook script $script from $REF"
        head -1 "$TMP/$script" | grep -q '^#!' || die "fetched $script is not a script"
        install -m 0755 "$TMP/$script" "$HOME/.claude/bin/$script"
    done

    curl -sSfL "$RAW/home/settings.json" -o "$TMP/settings.json" ||
        die "could not fetch home/settings.json from $REF"
    jq -e '.hooks' "$TMP/settings.json" > "$TMP/hooks.json" ||
        die "home/settings.json has no .hooks block"

    # Merge rather than overwrite. A container may already have a settings.json
    # -- this script's own earlier run, or something the environment put there
    # -- and replacing it wholesale would silently drop whatever else it holds.
    # `*` deep-merges objects and replaces arrays, so the hook lists this repo
    # owns are replaced while any other key survives untouched.
    #
    # Note ~/.claude/launcher-settings.json is a DIFFERENT file with its own
    # hooks, written by the harness. Nothing here touches it, and both are read.
    SETTINGS="$HOME/.claude/settings.json"
    if [ -f "$SETTINGS" ]; then
        jq -s '.[0] * {hooks: .[1]}' "$SETTINGS" "$TMP/hooks.json" > "$TMP/merged.json" ||
            die "could not merge into existing $SETTINGS"
        mv "$TMP/merged.json" "$SETTINGS"
        log "hooks   -> $SETTINGS (merged into existing)"
    else
        jq -n --slurpfile h "$TMP/hooks.json" '{hooks: $h[0]}' > "$SETTINGS" ||
            die "could not write $SETTINGS"
        log "hooks   -> $SETTINGS (created)"
    fi

    # prepush-guard needs gh, which these containers lack unless --with-gh was
    # given (#257), so without it it exits 0 here. precommit-claude-hook needs
    # the pre-commit framework and is a no-op without --with-precommit. Both
    # degrade rather than failing, which is why this flag has no hard
    # dependency on those -- but the trio is what makes it worth having.
    log "hooks   :  prchecks-wait, prepush-guard (needs --with-gh), precommit (needs --with-precommit)"
fi

# --- the manifest -------------------------------------------------------------
#
# Records what this run installed, so a later session can tell how old its
# container is. Nothing else knows: a cloud environment re-runs its setup script
# only when the script text changes, the allowed hosts change, or roughly seven
# days pass, so pushing to a branch does not reach new sessions -- they keep
# restoring the snapshot built the first time (#246).
#
# The credential helper solved its half server-side, by sending a version the
# broker can refuse (#182). Skills, policy and helper scripts have no server on
# the other end, so the skew is silent unless something writes down what it did.
#
# `git ls-remote` rather than the GitHub API: no token, no JSON parsing, and git
# is already required to be here. A REF that is already a commit SHA will not
# match a ref name, which is not a failure -- it is a pin, and pinned is the
# recommended state. Recorded as `pin` so a reader can tell "pinned" from
# "could not resolve".

MANIFEST="$HOME/.agents/.bootstrap-manifest"
mkdir -p "$HOME/.agents"

resolved=$(git ls-remote "https://github.com/pmgledhill102/agentic-coding-config" "$REF" 2>/dev/null |
    awk 'NR==1 {print $1}')
if [ -z "$resolved" ]; then
    case "$REF" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) resolved="$REF" ; kind=pin ;;
        *) resolved="unresolved" ; kind=unresolved ;;
    esac
else
    kind=ref
fi

{
    echo "ref=$REF"
    echo "ref_kind=$kind"
    echo "sha=$resolved"
    echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "profile=$PROFILE"
    echo "skills=$SKILLS $COMPOSED_SKILLS"
    echo "composed_skills=$COMPOSED_SKILLS"
    echo "helpers=$BIN_SCRIPTS"
    echo "precommit=$WITH_PRECOMMIT"
    echo "gcloud=$WITH_GCLOUD"
    echo "gh=$WITH_GH"
} > "$MANIFEST"
log "manifst -> $MANIFEST ($kind $(echo "$resolved" | cut -c1-12))"

# --- report -------------------------------------------------------------------
#
# The pinned ref is logged because a cached cloud environment can serve an older
# bootstrap than the one in main, and nothing else in a session says which
# vintage it is running.

log "done, from ${REF}"
log "note: commands and skills are read when Claude Code starts, so a session"
log "      already running will not see them until it restarts or resumes."
