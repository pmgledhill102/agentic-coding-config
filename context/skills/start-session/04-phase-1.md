## Phase 1 — Sync

Everything starts with one script call. The pre-flight check is inside it — including working out which repo this session is in when cwd is their parent — so
this command makes **no standalone Bash calls before the gather**.
