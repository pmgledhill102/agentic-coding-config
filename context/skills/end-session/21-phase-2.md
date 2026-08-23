## Phase 2 — Retrospective

If `main` CI is **failing** or **currently running** (per step 3), pre-prompt:

> `main` CI is `<failing|running>`. Defer the retrospective? (y/n)

On `y`: stop here. Re-run `end-session` later or run `retrospective` directly when ready.

Otherwise (or after the pre-prompt is dismissed with `n`), ask:

> Proceed to retrospective? (y/n)

On `y`: invoke the `retrospective` skill via the Skill tool. Do not perform the retrospective inline — let the skill own its contract.

On `n`: stop. The session is tidied; the user can run `retrospective` later if they change their mind.
