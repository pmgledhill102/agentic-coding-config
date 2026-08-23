### 7. Push main if ahead (Tier 2 — prompt)

```sh
git log origin/main..HEAD --oneline
```

If main is ahead of origin/main (shouldn't normally happen, but catches the case where commits landed locally):

- Ask before pushing.
