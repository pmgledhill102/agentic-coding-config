#!/bin/sh
# Behaviour tests for home/bin/dockerd-start-claude-hook.
#
# A SessionStart hook in the settings.json every surface reads, so both halves
# matter: in a cloud sandbox (CLAUDE_CODE_REMOTE=true, root, dockerd present)
# with no daemon it must start one, and everywhere else -- a workstation, a
# non-root user, an image without dockerd, a daemon that is already up -- it
# must start nothing. Every case must print nothing (a SessionStart hook's
# stdout reaches the agent's context) and exit 0 (a failing SessionStart hook
# is a session that starts with an error).
#
# docker and dockerd are stubs on a minimal PATH, so no real daemon is touched
# and the "dockerd absent" case is real. The stub daemon creates a marker file;
# the stub `docker info` succeeds only once it exists. The starting case is the
# positive control for every silent one: it proves the hook can start a daemon.
#
# Usage: sh tests/dockerd-start-hook-test.sh

set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK="$ROOT/home/bin/dockerd-start-claude-hook"

command -v setsid >/dev/null 2>&1 || {
  echo "SKIP: setsid not installed"
  exit 0
}

PASS=0
FAIL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# The tools the hook itself uses, and nothing else, so dockerd is absent unless
# a case adds the stub.
TOOLS="$WORK/tools"
mkdir -p "$TOOLS"
for t in sh id mkdir printf setsid nohup sleep; do
  p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$TOOLS/$t"
done

STUBS="$WORK/stubs"
mkdir -p "$STUBS"
cat >"$STUBS/docker" <<'EOF'
#!/bin/sh
[ "$1" = info ] && [ -e "$STUB_STATE/up" ]
EOF
cat >"$STUBS/dockerd" <<'EOF'
#!/bin/sh
echo started >>"$STUB_STATE/started"
: >"$STUB_STATE/up"
EOF
chmod +x "$STUBS/docker" "$STUBS/dockerd"

# run <name> <PATH> [VAR=value ...] -- leaves the stub state in $WORK/<name>,
# the hook's output in $WORK/<name>/out, and prints its exit status.
run() {
  name=$1
  path=$2
  shift 2
  state="$WORK/$name"
  mkdir -p "$state/etc"
  env -i PATH="$path" STUB_STATE="$state" \
    DOCKERD_START_CONFIG_DIR="$state/etc" DOCKERD_START_LOG="$state/dockerd.log" \
    DOCKERD_START_WAIT=3 "$@" \
    sh "$HOOK" >"$state/out" 2>&1 </dev/null
  echo $?
}

check() {
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
    echo "  ok    $1"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $1 (got '$2', want '$3')"
  fi
}

started() { [ -e "$WORK/$1/started" ] && echo yes || echo no; }
silent() { [ -s "$WORK/$1/out" ] && echo spoke || echo silent; }

WITH_STUBS="$STUBS:$TOOLS"

# The positive control: a sandbox with no daemon gets one.
rc=$(run start "$WITH_STUBS" CLAUDE_CODE_REMOTE=true DOCKERD_START_UID=0)
check "sandbox, no daemon: exits 0" "$rc" 0
check "sandbox, no daemon: dockerd started" "$(started start)" yes
check "sandbox, no daemon: silent" "$(silent start)" silent
check "sandbox, no daemon: mirror configured" \
  "$(grep -c 'mirror.gcr.io' "$WORK/start/etc/daemon.json" 2>/dev/null)" 1

# Idempotent: a second run, with the daemon now up, starts nothing more.
rc=$(run start "$WITH_STUBS" CLAUDE_CODE_REMOTE=true DOCKERD_START_UID=0)
check "second run: exits 0" "$rc" 0
check "second run: dockerd started exactly once" "$(wc -l <"$WORK/start/started" | tr -d ' ')" 1

# An existing daemon.json is somebody's choice and is left alone.
mkdir -p "$WORK/keep/etc"
printf '%s\n' '{"debug": true}' >"$WORK/keep/etc/daemon.json"
rc=$(run keep "$WITH_STUBS" CLAUDE_CODE_REMOTE=true DOCKERD_START_UID=0)
check "existing daemon.json: exits 0" "$rc" 0
check "existing daemon.json: left untouched" "$(cat "$WORK/keep/etc/daemon.json")" '{"debug": true}'
check "existing daemon.json: dockerd still started" "$(started keep)" yes

# Everything below must start nothing.
rc=$(run nonremote "$WITH_STUBS" DOCKERD_START_UID=0)
check "not a cloud sandbox: exits 0" "$rc" 0
check "not a cloud sandbox: no daemon" "$(started nonremote)" no
check "not a cloud sandbox: silent" "$(silent nonremote)" silent

rc=$(run nonroot "$WITH_STUBS" CLAUDE_CODE_REMOTE=true DOCKERD_START_UID=1000)
check "non-root: exits 0" "$rc" 0
check "non-root: no daemon" "$(started nonroot)" no

rc=$(run nodockerd "$TOOLS" CLAUDE_CODE_REMOTE=true DOCKERD_START_UID=0)
check "dockerd absent: exits 0" "$rc" 0
check "dockerd absent: silent" "$(silent nodockerd)" silent

mkdir -p "$WORK/up"
: >"$WORK/up/up"
rc=$(run up "$WITH_STUBS" CLAUDE_CODE_REMOTE=true DOCKERD_START_UID=0)
check "daemon already up: exits 0" "$rc" 0
check "daemon already up: no second daemon" "$(started up)" no

# A daemon that never comes up must not fail the session.
cat >"$WORK/dead-dockerd" <<'EOF'
#!/bin/sh
exit 1
EOF
mkdir -p "$WORK/deadstubs"
cp "$STUBS/docker" "$WORK/deadstubs/docker"
cp "$WORK/dead-dockerd" "$WORK/deadstubs/dockerd"
chmod +x "$WORK/deadstubs/docker" "$WORK/deadstubs/dockerd"
rc=$(run dead "$WORK/deadstubs:$TOOLS" CLAUDE_CODE_REMOTE=true DOCKERD_START_UID=0 DOCKERD_START_WAIT=1)
check "daemon never comes up: still exits 0" "$rc" 0
check "daemon never comes up: silent" "$(silent dead)" silent

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
