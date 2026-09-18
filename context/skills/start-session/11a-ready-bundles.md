### 6b. Ready bundles (Tier 1 — surface)

`/bundle-issues` triages the whole backlog in a session of its own and writes
what it found into **Bundle Issues** — open issues whose title starts with
`Bundle:`, each carrying the issues it covers, the files involved and the SHA it
was verified at. They are pre-triaged, verified work, which is why they outrank
the raw issue list in the brief.

Step 1 already produced the bundle rows; nothing extra is fetched here.

- **0 bundles**: skip silently. Do not suggest running `/bundle-issues` from
  here — no bundles is the normal state, and a prompt on every clean start is
  noise.
- **>= 1 bundle**: list them in the brief under `Ready bundles:`, above the
  other work sections.

There is no prompt and no chained command. A Bundle Issue is a self-contained
work order — it names its files, its gates, its stop rule, and tells whoever
picks it up to re-verify first — so working one is ordinary session work, picked
up the way any issue is. It is surfaced first because it is better-prepared
work, not because it needs special handling.
