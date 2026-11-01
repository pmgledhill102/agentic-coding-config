#!/bin/sh
# SessionStart hook: say so when a cloud container never ran cloud/bootstrap.sh.
#
# Everything the bootstrap delivers (the composed CLAUDE.md, the skills, the
# helpers under ~/.claude/bin) is invisible when it did not run, and nothing in
# the session says so: the agent works on without the PR-still-open rule, without
# /end-session, and without anyone knowing (#545). A script the bootstrap
# installs cannot report its own absence, so this one is committed in the repo
# and wired through the repo's .claude/settings.json, which a cloud session reads
# whether or not the environment's setup script ran.
#
# "Ran" is judged by two files either of which is enough: the manifest, which a
# failed run still writes (status=failed; the banner and start-session cover that
# case), and ~/.claude/bin, which a workstation has from chezmoi and has no
# manifest. Only cloud sessions are judged: CLAUDE_CODE_REMOTE is set there.
#
# Prints fixed wording only and starts no program, so it is instant and cannot
# fail a session. SessionStart stdout reaches the model as trusted context, which
# is why nothing read from the machine is ever echoed.

# shellcheck disable=SC2034 # line is never read; the loop only drains the input
while read -r line; do :; done

[ "${CLAUDE_CODE_REMOTE:-}" = true ] || exit 0
[ -n "${HOME:-}" ] || exit 0
[ -e "$HOME/.agents/.bootstrap-manifest" ] && exit 0
[ -d "$HOME/.claude/bin" ] && exit 0

echo "WARNING: this cloud container did not run the agentic-coding-config bootstrap. The managed CLAUDE.md policy, the skills (including /start-session and /end-session) and the helpers in ~/.claude/bin are NOT installed, so rules you would normally be given are missing. Tell the user before relying on them, and treat a missing skill or helper as expected, not as evidence the machine lacks it. The usual cause is the environment's setup script being empty or stale; see cloud/README.md, section \"Knowing whether a container is stale\"."
exit 0
