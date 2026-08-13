#!/bin/sh
# bootstrap.sh — install this repo's agent toolkit into a cloud sandbox.
#
# The one line a Claude Code cloud environment's setup script holds, so that
# everything of substance stays here, versioned, instead of being pasted into a
# vendor configuration field (ADR-0016, principle 5):
#
#   curl -sSL https://raw.githubusercontent.com/pmgledhill102/agentic-coding-config/<REF>/cloud/bootstrap.sh | sh -s -- <REF>
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

REF="${1:-main}"
RAW="https://raw.githubusercontent.com/pmgledhill102/agentic-coding-config/${REF}"

log() { echo "[bootstrap] $*"; }
die() { echo "[bootstrap] error: $*" >&2; exit 1; }

command -v curl > /dev/null 2>&1 || die "curl is required"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

log "installing from ${REF}"

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

# --- the skill, in both shapes -----------------------------------------------
#
# Placed under the container's own ~/.claude. Whether Claude Code reads a
# ~/.claude it did not create is the open question behind ADR-0016 principle 3:
# the documentation says user-scope config does not reach cloud sessions, but it
# means the developer's laptop does not transfer, which is a different claim
# from a directory that exists in the VM. Both shapes go down so one run answers
# both — commands/ is the current format, skills/ the direction of ADR-0014.
#
# Either way the content is provider-neutral; only the placement knows about
# Claude. That is the principle being tested, not a shortcut around it.

curl -sSfL "$RAW/home/commands/gcp-credentials.md" -o "$TMP/gcp-credentials.md" ||
    die "could not fetch the skill from $REF"

mkdir -p "$HOME/.claude/commands"
cp "$TMP/gcp-credentials.md" "$HOME/.claude/commands/gcp-credentials.md"
log "command -> $HOME/.claude/commands/gcp-credentials.md"

# SKILL.md wants frontmatter the command format does not carry. The first line
# of the command file is its description by convention, so lift it — single
# quoted, with any internal quote doubled, because that description contains a
# colon and would otherwise be read as a YAML mapping.
SKILL_DIR="$HOME/.claude/skills/gcp-credentials"
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
log "skill   -> $SKILL_DIR/SKILL.md"

# --- report -------------------------------------------------------------------
#
# The pinned ref is logged because a cached cloud environment can serve an older
# bootstrap than the one in main, and nothing else in a session says which
# vintage it is running.

log "done, from ${REF}"
log "note: commands and skills are read when Claude Code starts, so a session"
log "      already running will not see them until it restarts or resumes."
