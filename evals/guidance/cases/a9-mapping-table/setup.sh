#!/bin/sh
# A clone of a GitHub-hosted repo and a GitHub MCP stand-in. Issue #9 was
# filed today, so it is listed but not yet in the search index.
set -e
cd "$PROJ"
git init -q -b main .
git config user.name dev
git config user.email dev@example.invalid
git remote add origin https://github.com/example-org/webshop.git
mkdir tests
printf '# webshop\n\nThe shop.\n' >README.md
printf 'def test_login():\n    assert True\n' >tests/test_login.py
git add -A
git commit -q -m "Webshop skeleton"

cat >"$RUN_ROOT/mcp-state.json" <<'JSON'
{"issues": [
 {"number": 1, "id": 1001, "title": "Checkout page errors on an empty basket", "state": "closed", "labels": ["type: bug", "P1"], "created_at": "3 weeks ago", "parent": null},
 {"number": 3, "id": 1003, "title": "Test stability", "state": "open", "labels": ["type: epic", "P2"], "created_at": "2 weeks ago", "parent": null},
 {"number": 5, "id": 1005, "title": "Cart test times out on slow runners", "state": "open", "labels": ["type: bug", "P2"], "created_at": "2 weeks ago", "parent": 3},
 {"number": 6, "id": 1006, "title": "Add retry to payment sandbox calls", "state": "open", "labels": ["type: task", "P3"], "created_at": "9 days ago", "parent": null},
 {"number": 8, "id": 1008, "title": "Search test depends on the wall clock", "state": "open", "labels": ["type: bug", "P3"], "created_at": "4 days ago", "parent": 3},
 {"number": 9, "id": 1009, "title": "Login test flaky on CI", "state": "open", "labels": ["type: bug", "P2"], "created_at": "today", "parent": null, "indexed": false}
]}
JSON
cat >"$RUN_ROOT/mcp.json" <<JSON
{"mcpServers": {"github": {"command": "$(command -v python3)",
  "args": ["$STUBS/github_mcp.py"], "env": {"RUN_ROOT": "$RUN_ROOT"}}}}
JSON
