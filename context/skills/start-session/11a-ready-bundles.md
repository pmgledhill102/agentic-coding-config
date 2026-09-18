### 6b. Ready bundles (Tier 2 — prompt)

`/bundle-issues` triages the whole backlog in a session of its own and writes
what it found into **Bundle Issues** — open issues whose title starts with
`Bundle:`, each carrying the issues it covers, the files involved and the SHA it
was verified at. They are pre-triaged, verified work, which is why they outrank
the raw issue list in the brief.

Step 1 already produced the bundle rows; nothing extra is fetched here.

- **0 bundles**: skip silently. Do not suggest running `/bundle-issues` from
  here — an empty backlog of bundles is the normal state, and a prompt on every
  clean start is noise.
- **>= 1 bundle**: list them in the brief under `Ready bundles:` and prompt
  once:

  > `<N>` ready bundle(s). Run `/start-sweep-session` now? (y/n)

  - **yes** → invoke `/start-sweep-session`. It re-verifies each bundle against
    the current tree before touching anything, so a bundle that decayed since
    triage costs a check rather than a bad PR.
  - **no / empty / cancel** → carry on. The bundles keep; they are Issues, not
    session state.

This step surfaces and offers. It never works a bundle itself — `start-session`
is read-mostly, and a sweep cuts branches and opens PRs.
