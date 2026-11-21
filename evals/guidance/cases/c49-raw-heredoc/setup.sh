#!/bin/sh
# A JavaScript file whose string literal holds escaped newlines.
set -e
cd "$PROJ"
git init -q -b main .
git config user.name dev
git config user.email dev@example.invalid
mkdir cli
cat >cli/usage.js <<'JS'
"use strict";

const USAGE = "Usage: fmt-tool [options] <file>\n\nOptions:\n  -h, --help     show this help\n  -q, --quiet    print errors only\n";

module.exports = { USAGE };
JS
printf '# fmt-tool\n\nA small formatter.\n' >README.md
git add -A
git commit -q -m "fmt-tool skeleton"
