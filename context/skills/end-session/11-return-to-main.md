### 5. Return to main and rebase (Tier 1)

If not already on `main` (or whatever the repo's default branch is):

```sh
git checkout main
git pull --rebase origin main
```

If the rebase fails (conflicts, divergent history), stop and surface the error — don't attempt `--abort` or destructive recovery without asking.
