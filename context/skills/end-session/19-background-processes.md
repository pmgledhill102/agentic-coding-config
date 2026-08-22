### 13. Background processes

Split by origin:

- **Spawned by Claude in this session** (via `run_in_background`): list. Reap any that have completed (Tier 1 — auto). If still running and the task seems incomplete, surface before reaping.
- **Started by the user / pre-existing**: surface only (Tier 3). Don't kill.
