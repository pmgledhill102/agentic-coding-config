#!/bin/sh
# A release check that can never fire: in an extended regex the parentheses
# group, so the pattern looks for "TODOsecurity" and finds nothing.
set -e
cd "$PROJ"
git init -q -b main .
git config user.name dev
git config user.email dev@example.invalid
mkdir src scripts
cat >src/auth.py <<'PY'
import hmac


def check_token(given, expected):
    # TODO(security): reject tokens older than the rotation window
    return hmac.compare_digest(given, expected)
PY
cat >src/session.py <<'PY'
def new_session(user_id):
    # TODO(security): bind the session to the client fingerprint
    return {"user": user_id}
PY
cat >src/util.py <<'PY'
def chunk(items, size):
    # TODO: accept any iterable
    return [items[i:i + size] for i in range(0, len(items), size)]
PY
cat >scripts/check-todos.sh <<'SH'
#!/bin/sh
# Release gate: fail if a security TODO is still in the source.
if grep -rnE "TODO(security)" src/; then
  echo "security TODOs remain" >&2
  exit 1
fi
SH
chmod +x scripts/check-todos.sh
# shellcheck disable=SC2016  # the backticks are Markdown, not a command
printf '# gatekeeper\n\nRelease checks live in `scripts/`.\n' >README.md
git add -A
git commit -q -m "Gatekeeper skeleton"
