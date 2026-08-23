## Phase 2 — Retrospective

**Runs every time, unprompted.** When Phase 1 finishes, invoke the `retrospective` skill via the Skill tool. Do not ask first, and do not perform the retrospective inline — let the skill own its contract.

Why it is not opt-in: the retro is the step that generates the context every later session spends. A prompt turns that into a thing to decline at the exact moment the session feels finished, which is the moment it is least likely to be accepted, and the redesign in #263/#270 already cut what it costs to run.

Two things this deliberately does **not** gate on:

- **A red PR.** The retro is repo-read-only — it files journal drafts and Issues and changes no repo state — so a failing check is not a reason to defer it. Report the failure in the Phase 1 summary and run the retro anyway.
- **A short session.** A session with little in it produces a short retro, which costs little and still closes the loop on whatever the last one filed.

The user can always interrupt. What has changed is the default: running is what happens if nobody says otherwise.
