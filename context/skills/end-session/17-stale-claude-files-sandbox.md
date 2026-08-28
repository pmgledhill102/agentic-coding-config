### 11. Stale Claude commands/bin files (n/a here)

Not applicable on this surface, and the step number is kept so the two
compositions stay comparable.

This check exists because chezmoi never removes a target whose source was
deleted, so a retired slash command lingers at `~/.claude/commands/` on every
machine that ever applied a version containing it. There is no chezmoi here:
`~/.claude/` was written by `cloud/bootstrap.sh` when the container was built,
from an explicit list, and the container is discarded rather than updated in
place. Nothing accumulates.

Report it as `n/a (sandbox)` in the step 15 summary rather than omitting the
line, so a missing line is never ambiguous between "clean" and "not checked".
